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
global HotkeyConflicts
global HotkeyRegErrors
global PathCMappingByModSource
global PathCModSessions
global PathCModsUsed
global PathCSourceKeysUsed
global CONTEXT_MENU_DISMISS_DELAY

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

; For Path C, only register Up hotkeys on source keys that support key-up
SupportsKeyUpHotkey(hotkeyName) {
    baseKey := RegExReplace(hotkeyName, "^[~*$+!#^]+", "")
    return !RegExMatch(baseKey, "^Wheel")
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
    global HotkeyRegErrors := []
    global PathCMappingByModSource := Map()
    global PathCModSessions := Map()
    global PathCModsUsed := Map()
    global PathCSourceKeysUsed := Map()

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
ReloadAllHotkeys() {
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
        RegisterConfigHotkeys(cfg)
    for _, cfg in excludeConfigs
        RegisterConfigHotkeys(cfg)
    for _, cfg in globalConfigs
        RegisterConfigHotkeys(cfg)

    ; Register shared routing hotkeys for all Path C mappings
    RegisterAllPathCHotkeys()

    HotIf()

    ; Detect hotkey conflicts and update the status bar
    DetectHotkeyConflicts()
    UpdateStatusText()
}


; Reload hotkeys for a single config (implemented as full reload for now)
ReloadConfigHotkeys(configName := "") {
    ReloadAllHotkeys()
}

; Detect hotkey conflicts across enabled configs with overlapping scopes
; Conflict rules:
;   global vs any non-empty scope -> conflict
;   exclude vs exclude -> conflict (conservative strategy)
;   include vs include -> conflict when process lists intersect
;   include vs global -> conflict when include is non-empty
DetectHotkeyConflicts() {
    global HotkeyConflicts := []

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

        for idx, mapping in cfg["mappings"] {
            modKey := mapping["ModifierKey"]
            sourceKey := mapping["SourceKey"]
            if (modKey = "")
                hkStr := sourceKey
            else if (!mapping["PassthroughMod"])
                hkStr := modKey " & " sourceKey
            else
                hkStr := "~" modKey "+" sourceKey

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
                if (!mapping["PassthroughMod"]) {
                    if !modUsageB.Has(modKey)
                        modUsageB[modKey] := []
                    modUsageB[modKey].Push(scopeInfo)
                } else {
                    if !modUsageC.Has(modKey)
                        modUsageC[modKey] := []
                    modUsageC[modKey].Push(scopeInfo)
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
                    HotkeyConflicts.Push({
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
                    HotkeyConflicts.Push({
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
RegisterConfigHotkeys(cfg) {
    mappings := cfg["mappings"]
    if (mappings.Length = 0)
        return

    ; Create process checker closure (used by Path A/B; Path C checks scope in callbacks)
    checker := MakeProcessChecker(cfg)
    ; Keep a live reference to prevent closure GC
    if (checker != "")
        AllProcessCheckers.Push(checker)

    useCustomHotIf := (checker != "")

    ; Register all mappings under this config (A/B register hotkeys, C builds mapping table)
    for idx, mapping in mappings {
        RegisterMapping(mapping, useCustomHotIf, checker, cfg["name"] "|" idx, cfg["name"])
    }
}

; Register a single mapping by dispatching to Path A/B/C
RegisterMapping(mapping, useCustomHotIf, checker, uniqueIdx, configName) {
    modKey := mapping["ModifierKey"]

    ; Path A: no modifier, direct hotkey registration
    if (modKey = "") {
        if (useCustomHotIf)
            HotIf(checker)
        else
            HotIf()
        hkInfo := MakeActiveHotkeyRecord(checker, configName)
        RegisterPathA(mapping, hkInfo, uniqueIdx)
        ActiveHotkeys.Push(hkInfo)
        return
    }

    ; Path B: intercepting combo hotkey (modKey & sourceKey), modifier does not pass through
    if (!mapping["PassthroughMod"]) {
        if (useCustomHotIf)
            HotIf(checker)
        else
            HotIf()
        hkInfo := MakeActiveHotkeyRecord(checker, configName)
        RegisterPathB(mapping, hkInfo, uniqueIdx, checker, configName)
        ActiveHotkeys.Push(hkInfo)
        return
    }

    ; Path C: stateful passthrough, handled by Path C engine instead of direct target callback
    HotIf()
    RegisterPathCMapping(mapping, uniqueIdx, configName, checker)
}

; Path A: no modifier, directly map sourceKey -> targetKey
RegisterPathA(mapping, hkInfo, uniqueIdx) {
    sourceKey := mapping["SourceKey"]
    targetKey := mapping["TargetKey"]
    holdRepeat := mapping["HoldRepeat"]

    hkInfo.key := sourceKey

    if (holdRepeat) {
        downCb := HoldDownCallback.Bind(targetKey, mapping["RepeatDelay"], mapping["RepeatInterval"], uniqueIdx, sourceKey)
        upCb := HoldUpCallback.Bind(uniqueIdx)
        try {
            Hotkey(sourceKey, downCb, "On")
            Hotkey(sourceKey " Up", upCb, "On")
            hkInfo.keyUp := sourceKey " Up"
        } catch as e {
            HotkeyRegErrors.Push(sourceKey)
        }
    } else {
        try Hotkey(sourceKey, SendKeyCallback.Bind(targetKey), "On")
        catch as e
            HotkeyRegErrors.Push(sourceKey)
    }
}

; Path B: intercepting combo hotkey (modKey & sourceKey), modifier does not pass through
RegisterPathB(mapping, hkInfo, uniqueIdx, checker, configName) {
    modKey := mapping["ModifierKey"]
    sourceKey := mapping["SourceKey"]
    targetKey := mapping["TargetKey"]
    holdRepeat := mapping["HoldRepeat"]
    comboKey := modKey " & " sourceKey

    hkInfo.key := comboKey

    if (holdRepeat) {
        downCb := HoldDownCallback.Bind(targetKey, mapping["RepeatDelay"], mapping["RepeatInterval"], uniqueIdx, sourceKey)
        upCb := HoldUpCallback.Bind(uniqueIdx)
        try {
            Hotkey(comboKey, downCb, "On")
            Hotkey(comboKey " Up", upCb, "On")
            hkInfo.keyUp := comboKey " Up"
        } catch as e {
            HotkeyRegErrors.Push(comboKey)
        }
    } else {
        try Hotkey(comboKey, SendKeyCallback.Bind(targetKey), "On")
        catch as e
            HotkeyRegErrors.Push(comboKey)
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
            HotkeyRegErrors.Push(modKey)
        }
    }
}

; Path C: only build the mapping table; runtime behavior is handled by the Path C engine
RegisterPathCMapping(mapping, uniqueIdx, configName, checker) {
    global PathCMappingByModSource, PathCModsUsed, PathCSourceKeysUsed

    modKey := mapping["ModifierKey"]
    sourceKey := mapping["SourceKey"]
    if (modKey = "" || !mapping["PassthroughMod"])
        return

    key := modKey "|" sourceKey
    if !PathCMappingByModSource.Has(key)
        PathCMappingByModSource[key] := []

    entry := {
        modKey: modKey,
        sourceKey: sourceKey,
        targetKey: mapping["TargetKey"],
        holdRepeat: mapping["HoldRepeat"],
        repeatDelay: mapping["RepeatDelay"],
        repeatInterval: mapping["RepeatInterval"],
        configName: configName,
        id: uniqueIdx,
        checker: checker
    }
    PathCMappingByModSource[key].Push(entry)

    PathCModsUsed[modKey] := true
    PathCSourceKeysUsed[sourceKey] := true
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

RepeatTimerCallback(sendKey, sourceKey, idx, modKey := "", *) {
    ; For Path C: ensure modifier is still held
    if (modKey != "" && !GetKeyState(modKey, "P")) {
        StopHoldTimer(idx)
        return
    }
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

; ============================================================================
; Path C engine (explicit state machine + unified event routing)
; ============================================================================

; Register all Path C modifier/source hotkeys after config registration completes
RegisterAllPathCHotkeys() {
    global PathCModsUsed, PathCSourceKeysUsed, ActiveHotkeys, HotkeyRegErrors

    ; Modifiers: keyboard/mouse keys all use "~modKey" / "~modKey Up" to pass through events
    for modKey, _ in PathCModsUsed {
        if (modKey = "")
            continue

        downHk := "~" modKey
        upHk := "~" modKey " Up"

        try {
            HotIf()
            Hotkey(downHk, PathC_ModDownCallback.Bind(modKey), "On")
            Hotkey(upHk, PathC_ModUpCallback.Bind(modKey), "On")
        } catch as e {
            HotkeyRegErrors.Push(downHk)
            continue
        }

        modHkInfo := MakeActiveHotkeyRecord("", "", downHk, upHk)
        ActiveHotkeys.Push(modHkInfo)
    }

    ; Source keys: listen centrally and let Path C decide what to trigger
    for sourceKey, _ in PathCSourceKeysUsed {
        if (sourceKey = "")
            continue

        sourceHotkey := SubStr(sourceKey, 1, 1) = "*" ? sourceKey : "*" sourceKey

        ; KeyDown
        hkInfo := MakeActiveHotkeyRecord("", "", sourceHotkey)

        try {
            HotIf()
            Hotkey(sourceHotkey, PathC_SourceDownCallback.Bind(sourceKey), "On")
        } catch as e {
            HotkeyRegErrors.Push(sourceHotkey)
        }

        ; KeyUp: only for source keys that support Up hotkeys
        if (SupportsKeyUpHotkey(sourceHotkey)) {
            srcUpHotkey := sourceHotkey " Up"
            try {
                HotIf()
                Hotkey(srcUpHotkey, PathC_SourceUpCallback.Bind(sourceKey), "On")
                hkInfo.keyUp := srcUpHotkey
            } catch as e {
                HotkeyRegErrors.Push(srcUpHotkey)
            }
        }
        ActiveHotkeys.Push(hkInfo)
    }

    HotIf()
}

; Get or initialize the session state for a modifier key
PathC_GetSession(modKey) {
    global PathCModSessions
    if !PathCModSessions.Has(modKey) {
        PathCModSessions[modKey] := {
            state: "Idle",
            isGesture: false,
            activeSources: Map(),
            repeatMappings: Map()
        }
    }
    return PathCModSessions[modKey]
}

; End a modifier session: stop all repeats and reset state
PathC_EndSession(modKey) {
    global PathCModSessions, HoldTimers
    if !PathCModSessions.Has(modKey)
        return

    session := PathCModSessions[modKey]

    ; Stop all repeat timers associated with this modifier
    for mappingId, _ in session.repeatMappings {
        StopHoldTimer(mappingId)
    }

    session.repeatMappings := Map()
    session.activeSources := Map()
    session.state := "Idle"
    session.isGesture := false
}

; Whether a mapping is active in the current foreground window (using checker closure)
PathC_IsMappingActive(mapping) {
    if (mapping.HasOwnProp("checker") && mapping.checker != "") {
        try
            return mapping.checker.Call()
        catch
            return false
    }
    return true
}

; Start Path C long-press repeat for a mapping
PathC_StartRepeat(mapping, modKey, sourceKey) {
    global HoldTimers

    idx := mapping.id
    sendKey := KeyToSendFormat(mapping.targetKey)

    ; Defensive cleanup: stop any existing timer to avoid orphan timers on re-entry
    StopHoldTimer(idx)

    DispatchSend(sendKey)

    timerFn := RepeatTimerCallback.Bind(sendKey, sourceKey, idx, modKey)
    startFn := StartRepeat.Bind(idx, timerFn, mapping.repeatInterval)
    HoldTimers[idx] := { fn: timerFn, startFn: startFn, interval: mapping.repeatInterval, active: true }
    SetTimer(startFn, -mapping.repeatDelay)
}

; Path C modifier-key down callback (shared entry point)
PathC_ModDownCallback(modKey, *) {
    session := PathC_GetSession(modKey)

    ; Force-end any unfinished session before starting a new one
    if (session.state != "Idle")
        PathC_EndSession(modKey)

    session := PathC_GetSession(modKey)
    session.state := "HeldNoCombo"
    session.isGesture := false
    session.activeSources := Map()
    session.repeatMappings := Map()
}

; Path C modifier-key up callback (shared entry point)
PathC_ModUpCallback(modKey, *) {
    session := PathC_GetSession(modKey)
    if (session.state = "Idle") {
        return
    }

    isGesture := session.isGesture

    ; For RButton, only dismiss a possible context menu if this session actually triggered a Path C gesture.
    ; Sending Escape keeps browser-style right-button gestures usable.
    if (modKey = "RButton" && isGesture) {
        SetTimer(PathC_DismissContextMenu, -CONTEXT_MENU_DISMISS_DELAY)
    }

    PathC_EndSession(modKey)
}

PathC_DismissContextMenu(*) {
    DispatchSend("{Escape}")
}

; Path C source-key down callback (shared entry point)
PathC_SourceDownCallback(sourceKey, *) {
    global PathCMappingByModSource, PathCModSessions

    handled := false

    ; Iterate all currently active modifier sessions
    for modKey, session in PathCModSessions {
        if (session.state = "Idle")
            continue

        key := modKey "|" sourceKey
        if !PathCMappingByModSource.Has(key)
            continue

        mappings := PathCMappingByModSource[key]

        for _, mapping in mappings {
            if !PathC_IsMappingActive(mapping)
                continue

            ; Mark this session as a gesture session
            session.state := "GestureActive"
            session.isGesture := true

            if (mapping.holdRepeat) {
                PathC_StartRepeat(mapping, modKey, sourceKey)
                session.repeatMappings[mapping.id] := true

                if !session.activeSources.Has(sourceKey)
                    session.activeSources[sourceKey] := []
                session.activeSources[sourceKey].Push(mapping.id)
            } else {
                DispatchSend(KeyToSendFormat(mapping.targetKey))
            }

            handled := true
            break
        }

        if (handled)
            break
    }

    if (!handled) {
        ; No Path C mapping matched, fall back to the raw source key
        DispatchSend(KeyToSendFormat(sourceKey))
    }
}

; Path C source-key up callback (shared entry point, only for keys that support Up)
PathC_SourceUpCallback(sourceKey, *) {
    global PathCModSessions

    for modKey, session in PathCModSessions {
        if (session.state = "Idle")
            continue
        if !session.activeSources.Has(sourceKey)
            continue

        ids := session.activeSources[sourceKey]
        for _, mappingId in ids {
            StopHoldTimer(mappingId)
            if (session.repeatMappings.Has(mappingId))
                session.repeatMappings.Delete(mappingId)
        }
        session.activeSources.Delete(sourceKey)
    }
}
