; ============================================================================
; AHKeyMap - Hotkey engine module
; Registers hotkeys, routes callbacks, and handles long-press repeat
; ============================================================================

; Globals shared across modules
global AllConfigs
global ActiveHotkeys
global HoldTimers
global InterceptModKeys
global AllProcessCheckers
global ForegroundProcessHook

; ============================================================================
; Hotkey engine core
; ============================================================================

; Factory for process-matching closures
; Returns a HotIf predicate based on config's processMode
MakeProcessChecker(cfg) {
    mode := cfg["processMode"]
    if (mode = "include") {
        procList := cfg["processList"]
        if (procList.Length = 0)
            return ""
        return (*) => CheckIncludeMatch(procList)
    } else if (mode = "exclude") {
        exclList := cfg["excludeProcessList"]
        if (exclList.Length = 0)
            return ""
        return (*) => CheckExcludeMatch(exclList)
    }
    return ""
}

NormalizeProcessName(procName) {
    return StrLower(Trim(procName))
}

GetForegroundProcessName() {
    ; Test seam: when set, the hook replaces the OS foreground-process query
    if (ForegroundProcessHook != "") {
        return NormalizeProcessName(ForegroundProcessHook.Call())
    }

    try
        return NormalizeProcessName(WinGetProcessName("A"))
    catch
        return ""
}

ProcessListContains(procList, procName) {
    normalizedProc := NormalizeProcessName(procName)
    if (normalizedProc = "")
        return false

    for listedProc in procList {
        if (NormalizeProcessName(listedProc) = normalizedProc)
            return true
    }
    return false
}

; include mode: true when foreground window matches any process in the list
CheckIncludeMatch(procList) {
    fgProc := GetForegroundProcessName()
    return (fgProc != "" && ProcessListContains(procList, fgProc))
}

; exclude mode: true when foreground process is not in the excluded list
CheckExcludeMatch(exclList) {
    fgProc := GetForegroundProcessName()
    return (fgProc != "" && !ProcessListContains(exclList, fgProc))
}

; Append a unique value to an array
AddUniqueArrayValue(arr, value) {
    for _, existingValue in arr {
        if (existingValue = value)
            return
    }
    arr.Push(value)
}

; Append every element of src to dest (in order)
AppendAll(dest, src) {
    for _, value in src
        dest.Push(value)
}

MakeActiveHotkeyRecord(checker := "", configName := "", key := "", keyUp := "") {
    return {
        checker: checker,
        configName: configName,
        key: key,
        keyUp: keyUp
    }
}

; Unregister all currently active hotkeys
UnregisterAllHotkeys() {
    ; Build a lightweight snapshot first to avoid mutating the source structure while iterating
    hotkeysSnapshot := []
    for _, hk in ActiveHotkeys {
        if !IsObject(hk)
            continue

        checkerVal := ""
        keyVal := ""
        keyUpVal := ""

        try {
            if (hk.HasOwnProp("key"))
                keyVal := hk.key
        } catch {
            continue
        }
        if (keyVal = "")
            continue

        try {
            if (hk.HasOwnProp("checker") && hk.checker != "")
                checkerVal := hk.checker
        }

        try {
            if (hk.HasOwnProp("keyUp"))
                keyUpVal := hk.keyUp
        }

        hotkeysSnapshot.Push({ checker: checkerVal, key: keyVal, keyUp: keyUpVal })
    }

    ; Clear global state immediately so later logic does not hold stale references
    HotIf()
    global ActiveHotkeys := []
    global InterceptModKeys := Map()
    global HoldTimers := Map()
    global AllProcessCheckers := []

    ; Path C hotkeys and state are owned by the Path C engine
    PathCEngine.Instance.Reset()

    ; Then disable each hotkey from the snapshot, ignoring script-level cleanup errors
    for _, info in hotkeysSnapshot {
        try {
            if (info.checker != "")
                HotIf(info.checker)
            else
                HotIf()

            if (info.key != "")
                Hotkey(info.key, "Off")
            if (info.keyUp != "")
                Hotkey(info.keyUp, "Off")
        } catch {
            continue
        }
    }
    HotIf()
}

; Reload hotkeys for all enabled configs
; Returns the engine output as a Map: {conflicts: [...], regErrors: [...]}
ReloadAllHotkeys() {
    regErrors := []
    UnregisterAllHotkeys()

    ; Split configs by scope priority: include > exclude > global
    includeConfigs := []
    excludeConfigs := []
    globalConfigs := []

    for _, cfg in AllConfigs {
        if (!cfg["enabled"])
            continue
        if (cfg["mappings"].Length = 0)
            continue

        mode := cfg["processMode"]
        if (mode = "include")
            includeConfigs.Push(cfg)
        else if (mode = "exclude")
            excludeConfigs.Push(cfg)
        else
            globalConfigs.Push(cfg)
    }

    ; Register in priority order: include first (most specific), global last
    for _, cfg in includeConfigs
        AppendAll(regErrors, RegisterConfigHotkeys(cfg))
    for _, cfg in excludeConfigs
        AppendAll(regErrors, RegisterConfigHotkeys(cfg))
    for _, cfg in globalConfigs
        AppendAll(regErrors, RegisterConfigHotkeys(cfg))

    ; Register shared routing hotkeys for all Path C mappings
    AppendAll(regErrors, PathCEngine.Instance.Commit())

    HotIf()

    return { conflicts: DetectHotkeyConflicts(), regErrors: regErrors }
}

; Detect hotkey conflicts across enabled configs with overlapping scopes
; Pure function: reads AllConfigs, returns the conflict array, touches nothing
; Conflict rules:
;   global vs any non-empty scope -> conflict
;   exclude vs exclude -> conflict (conservative strategy)
;   include vs include -> conflict when process lists intersect
;   include vs global -> conflict when include is non-empty
DetectHotkeyConflicts() {
    conflicts := []

    ; Collect mappings from enabled configs together with scope metadata
    hotkeyGroups := Map()
    modUsageB := Map()
    modUsageC := Map()

    for _, cfg in AllConfigs {
        if (!cfg["enabled"])
            continue
        if (cfg["mappings"].Length = 0)
            continue

        mode := cfg["processMode"]
        ; procKey distinguishes process lists for include/exclude scopes
        if (mode = "include")
            procKey := CanonicalizeProcessScope(cfg["process"])
        else if (mode = "exclude")
            procKey := CanonicalizeProcessScope(cfg["excludeProcess"])
        else
            procKey := ""

        for idx, m in cfg["mappings"] {
            hkStr := Mapping.HotkeyStringFor(m)
            modKey := m["ModifierKey"]

            entry := {
                hotkey: hkStr,
                configName: cfg["name"],
                mappingIdx: idx,
                mode: mode,
                procKey: procKey
            }

            if !hotkeyGroups.Has(hkStr)
                hotkeyGroups[hkStr] := []
            hotkeyGroups[hkStr].Push(entry)

            ; Collect modifier usage by path for cross-path B/C conflict detection
            if (modKey != "") {
                scopeInfo := { configName: cfg["name"], mode: mode, procKey: procKey }
                if (Mapping.ClassifyPath(m) = Mapping.PATH_C) {
                    if !modUsageC.Has(modKey)
                        modUsageC[modKey] := []
                    modUsageC[modKey].Push(scopeInfo)
                } else {
                    if !modUsageB.Has(modKey)
                        modUsageB[modKey] := []
                    modUsageB[modKey].Push(scopeInfo)
                }
            }
        }
    }

    ; Compare entries within each hotkey group only
    for _, group in hotkeyGroups {
        if (group.Length < 2)
            continue
        i := 1
        while (i <= group.Length) {
            j := i + 1
            while (j <= group.Length) {
                a := group[i]
                b := group[j]
                if ScopesOverlap(a.mode, a.procKey, b.mode, b.procKey) {
                    conflicts.Push({
                        hotkey: a.hotkey,
                        config1: a.configName,
                        idx1: a.mappingIdx,
                        config2: b.configName,
                        idx2: b.mappingIdx
                    })
                }
                j++
            }
            i++
        }
    }

    ; Detect cross-path B/C modifier conflicts (same modifier in intercept and passthrough modes)
    for modKey, bEntries in modUsageB {
        if !modUsageC.Has(modKey)
            continue
        cEntries := modUsageC[modKey]
        for _, bEntry in bEntries {
            for _, cEntry in cEntries {
                if ScopesOverlap(bEntry.mode, bEntry.procKey, cEntry.mode, cEntry.procKey) {
                    conflicts.Push({
                        hotkey: modKey " (Path B/C conflict)",
                        config1: bEntry.configName,
                        idx1: 0,
                        config2: cEntry.configName,
                        idx2: 0
                    })
                }
            }
        }
    }
    return conflicts
}

; Normalize include process list into a comparable scope key:
; trim, dedupe, lower-case, sort, then join with |
CanonicalizeProcessScope(procStr) {
    procSet := Map()
    loop parse procStr, "|" {
        procName := StrLower(Trim(A_LoopField))
        if (procName != "")
            procSet[procName] := true
    }

    if (procSet.Count = 0)
        return ""

    procList := []
    for procName, _ in procSet
        procList.Push(procName)

    ; Use a simple sort here to avoid extra dependencies for small lists
    i := 1
    while (i < procList.Length) {
        j := i + 1
        while (j <= procList.Length) {
            if (StrCompare(procList[j], procList[i]) < 0) {
                tmp := procList[i]
                procList[i] := procList[j]
                procList[j] := tmp
            }
            j++
        }
        i++
    }

    result := ""
    for _, procName in procList {
        if (result != "")
            result .= "|"
        result .= procName
    }
    return result
}

; Whether two include scopes overlap
IncludeScopesOverlap(procKey1, procKey2) {
    if (procKey1 = "" || procKey2 = "")
        return false

    list1 := StrSplit(procKey1, "|")
    list2 := StrSplit(procKey2, "|")

    ; Build a set from the shorter list to reduce lookups
    if (list1.Length > list2.Length) {
        tmp := list1
        list1 := list2
        list2 := tmp
    }

    procSet := Map()
    for _, procName in list1
        procSet[procName] := true

    for _, procName in list2 {
        if (procSet.Has(procName))
            return true
    }
    return false
}

; Whether an include scope overlaps with an exclude scope
; Condition: include contains at least one process not present in exclude
IncludeVsExcludeOverlap(includeKey, excludeKey) {
    if (includeKey = "")
        return false
    if (excludeKey = "")
        return true

    excludeSet := ScopeKeyToSet(excludeKey)
    loop parse includeKey, "|" {
        procName := A_LoopField
        if (!excludeSet.Has(procName))
            return true
    }
    return false
}

; Parse scopeKey (a.exe|b.exe) into a Map-based set
ScopeKeyToSet(scopeKey) {
    procSet := Map()
    if (scopeKey = "")
        return procSet

    loop parse scopeKey, "|" {
        procName := A_LoopField
        if (procName != "")
            procSet[procName] := true
    }
    return procSet
}

; Determine whether two scopes overlap
; If there exists any process where both scopes could be active, they overlap
ScopesOverlap(mode1, procKey1, mode2, procKey2) {
    ; include/include: overlap only if the lists intersect
    if (mode1 = "include" && mode2 = "include")
        return IncludeScopesOverlap(procKey1, procKey2)

    ; include/global: any non-empty include overlaps with global
    if (mode1 = "include" && mode2 = "global")
        return (procKey1 != "")
    if (mode2 = "include" && mode1 = "global")
        return (procKey2 != "")

    ; include/exclude: overlap when include contains a non-excluded process
    if (mode1 = "include" && mode2 = "exclude")
        return IncludeVsExcludeOverlap(procKey1, procKey2)
    if (mode2 = "include" && mode1 = "exclude")
        return IncludeVsExcludeOverlap(procKey2, procKey1)

    ; global overlaps with both exclude and global
    if (mode1 = "global" || mode2 = "global")
        return true

    ; exclude/exclude: conservatively treat as overlapping
    return true
}

; Register all hotkeys for a single config
; Returns the array of hotkey names that failed registration
RegisterConfigHotkeys(cfg) {
    regErrors := []
    mappings := cfg["mappings"]
    if (mappings.Length = 0)
        return regErrors

    ; Create process checker closure (used by Path A/B; Path C checks scope in callbacks)
    checker := MakeProcessChecker(cfg)
    ; Keep a live reference to prevent closure GC
    if (checker != "")
        AllProcessCheckers.Push(checker)

    useCustomHotIf := (checker != "")

    ; Register all mappings under this config (A/B register hotkeys, C builds mapping table)
    for idx, mapping in mappings {
        AppendAll(regErrors, RegisterMapping(mapping, useCustomHotIf, checker, cfg["name"] "|" idx, cfg["name"]))
    }
    return regErrors
}

; Register a single mapping by dispatching to Path A/B/C
; Returns the array of hotkey names that failed registration
; (local name avoids shadowing the Mapping class; AHK names are case-insensitive)
RegisterMapping(m, useCustomHotIf, checker, uniqueIdx, configName) {
    regErrors := []
    path := Mapping.ClassifyPath(m)

    ; Path A: no modifier, direct hotkey registration
    if (path = Mapping.PATH_A) {
        if (useCustomHotIf)
            HotIf(checker)
        else
            HotIf()
        hkInfo := MakeActiveHotkeyRecord(checker, configName)
        RegisterPathA(m, hkInfo, uniqueIdx, regErrors)
        ActiveHotkeys.Push(hkInfo)
        return regErrors
    }

    ; Path B: intercepting combo hotkey (modKey & sourceKey), modifier does not pass through
    if (path = Mapping.PATH_B) {
        if (useCustomHotIf)
            HotIf(checker)
        else
            HotIf()
        hkInfo := MakeActiveHotkeyRecord(checker, configName)
        RegisterPathB(m, hkInfo, uniqueIdx, checker, configName, regErrors)
        ActiveHotkeys.Push(hkInfo)
        return regErrors
    }

    ; Path C: stateful passthrough, handled by Path C engine instead of direct target callback
    HotIf()
    PathCEngine.Instance.AddMapping(m, uniqueIdx, configName, checker)
    return regErrors
}

; Path A: no modifier, directly map sourceKey -> targetKey
RegisterPathA(m, hkInfo, uniqueIdx, regErrors) {
    sourceKey := m["SourceKey"]
    targetKey := m["TargetKey"]
    holdRepeat := m["HoldRepeat"]

    hkInfo.key := sourceKey

    if (holdRepeat) {
        downCb := HoldDownCallback.Bind(targetKey, m["RepeatDelay"], m["RepeatInterval"], uniqueIdx, sourceKey)
        upCb := HoldUpCallback.Bind(uniqueIdx)
        try {
            Hotkey(sourceKey, downCb, "On")
            Hotkey(sourceKey " Up", upCb, "On")
            hkInfo.keyUp := sourceKey " Up"
        } catch as e {
            regErrors.Push(sourceKey)
        }
    } else {
        try Hotkey(sourceKey, SendKeyCallback.Bind(targetKey), "On")
        catch as e
            regErrors.Push(sourceKey)
    }
}

; Path B: intercepting combo hotkey (modKey & sourceKey), modifier does not pass through
RegisterPathB(m, hkInfo, uniqueIdx, checker, configName, regErrors) {
    modKey := m["ModifierKey"]
    sourceKey := m["SourceKey"]
    targetKey := m["TargetKey"]
    holdRepeat := m["HoldRepeat"]
    comboKey := Mapping.HotkeyStringFor(m)

    hkInfo.key := comboKey

    if (holdRepeat) {
        downCb := HoldDownCallback.Bind(targetKey, m["RepeatDelay"], m["RepeatInterval"], uniqueIdx, sourceKey)
        upCb := HoldUpCallback.Bind(uniqueIdx)
        try {
            Hotkey(comboKey, downCb, "On")
            Hotkey(comboKey " Up", upCb, "On")
            hkInfo.keyUp := comboKey " Up"
        } catch as e {
            regErrors.Push(comboKey)
        }
    } else {
        try Hotkey(comboKey, SendKeyCallback.Bind(targetKey), "On")
        catch as e
            regErrors.Push(comboKey)
    }

    ; Register modifier restore hotkey only once per HotIf scope
    modRegKey := (checker != "" ? configName : "") "|" modKey
    if !InterceptModKeys.Has(modRegKey) {
        try {
            Hotkey(modKey, RestoreModKeyCallback.Bind(modKey), "On")
            modHkInfo := MakeActiveHotkeyRecord(checker, configName, modKey)
            ActiveHotkeys.Push(modHkInfo)
            InterceptModKeys[modRegKey] := true
        } catch as e {
            regErrors.Push(modKey)
        }
    }
}

; ============================================================================
; Path A/B callbacks
; ============================================================================

SendKeyCallback(targetKey, *) {
    DispatchSend(KeyToSendFormat(targetKey))
}

HoldDownCallback(targetKey, repeatDelay, repeatInterval, idx, sourceKey, *) {
    ; Defensive cleanup: stop existing timer to avoid orphaned timers on re-entry
    StopHoldTimer(idx)

    sendKey := KeyToSendFormat(targetKey)
    DispatchSend(sendKey)

    timerFn := RepeatTimerCallback.Bind(sendKey, sourceKey, idx)
    startFn := StartRepeat.Bind(idx, timerFn, repeatInterval)
    HoldTimers[idx] := { fn: timerFn, startFn: startFn, interval: repeatInterval, active: true }
    SetTimer(startFn, -repeatDelay)
}

StartRepeat(idx, timerFn, interval, *) {
    if (HoldTimers.Has(idx) && HoldTimers[idx].active)
        SetTimer(timerFn, interval)
}

StopHoldTimer(idx) {
    if HoldTimers.Has(idx) {
        if (HoldTimers[idx].HasProp("fn"))
            SetTimer(HoldTimers[idx].fn, 0)
        if (HoldTimers[idx].HasProp("startFn"))
            SetTimer(HoldTimers[idx].startFn, 0)
        HoldTimers[idx].active := false
        HoldTimers.Delete(idx)
    }
}

RepeatTimerCallback(sendKey, sourceKey, idx, *) {
    ; Safety check: stop repeating if the source key has been released (non-wheel keys)
    baseKey := RegExReplace(sourceKey, "^[+!#^]+", "")
    if (baseKey != "" && !RegExMatch(baseKey, "^Wheel") && !GetKeyState(baseKey, "P")) {
        StopHoldTimer(idx)
        return
    }
    DispatchSend(sendKey)
}

HoldUpCallback(idx, *) {
    StopHoldTimer(idx)
}

ShouldRestoreModifierOnSoloPress(modKey) {
    return !IsMouseButtonKey(modKey)
}

RestoreModKeyCallback(modKey, *) {
    if !ShouldRestoreModifierOnSoloPress(modKey)
        return

    DispatchSend(KeyToSendFormat(modKey))
}
