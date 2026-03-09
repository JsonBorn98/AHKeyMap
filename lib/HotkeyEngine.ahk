; ============================================================================
; AHKeyMap - 热键引擎模块
; 负责热键注册、回调处理、长按连续触发等核心功能
; ============================================================================

; 声明跨文件使用的全局变量
global AllConfigs
global ActiveHotkeys
global HoldTimers
global ComboFiredState
global PassthroughModKeys
global InterceptModKeys
global PassthroughHandlers
global PassthroughSourceRegistered
global AllProcessCheckers
global HotkeyConflicts
global HotkeyRegErrors
global CONTEXT_MENU_DISMISS_DELAY

; ============================================================================
; 热键引擎核心
; ============================================================================

; 创建进程匹配闭包工厂函数
; 根据配置的 processMode 返回对应的 HotIf 条件函数
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

; include 模式：前台窗口匹配任一进程时返回 true
CheckIncludeMatch(procList) {
    for procName in procList {
        if WinActive("ahk_exe " procName)
            return true
    }
    return false
}

; exclude 模式：前台窗口不在排除列表中时返回 true
CheckExcludeMatch(exclList) {
    try
        fgProc := WinGetProcessName("A")
    catch
        return false
    for procName in exclList {
        if (fgProc = procName)
            return false
    }
    return true
}

; 卸载所有当前热键
UnregisterAllHotkeys() {
    ; 先清理状态追踪式修饰键
    CleanupPassthroughModKeys()

    ; 卸载所有已注册的热键
    for _, hk in ActiveHotkeys {
        try {
            ; 防御性检查：确保 hk 是有效的 Map 对象
            if (Type(hk) != "Map")
                continue

            if (hk.Has("checker") && hk["checker"] != "")
                HotIf(hk["checker"])
            else
                HotIf()

            Hotkey(hk["key"], "Off")
            if (hk.Has("keyUp"))
                Hotkey(hk["keyUp"], "Off")
        }
    }
    HotIf()
    global ActiveHotkeys := []
    global ComboFiredState := Map()
    global PassthroughModKeys := Map()
    global InterceptModKeys := Map()
    global PassthroughHandlers := Map()
    global PassthroughSourceRegistered := Map()
    global HoldTimers := Map()
    global AllProcessCheckers := []
    global HotkeyRegErrors := []
}

; 重新加载所有已启用配置的热键
ReloadAllHotkeys() {
    UnregisterAllHotkeys()

    ; 按优先级排序：include > exclude > global
    ; 收集各类配置
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

    ; 按优先级注册：include 最先（最具体），global 最后
    for _, cfg in includeConfigs
        RegisterConfigHotkeys(cfg)
    for _, cfg in excludeConfigs
        RegisterConfigHotkeys(cfg)
    for _, cfg in globalConfigs
        RegisterConfigHotkeys(cfg)

    HotIf()

    ; 检测热键冲突并更新状态栏
    DetectHotkeyConflicts()
    UpdateStatusText()
}


; 重载单个配置的热键（因修饰键共享状态，当前实现为全量重载）
ReloadConfigHotkeys(configName := "") {
    ReloadAllHotkeys()
}

; 检测热键冲突：扫描所有已启用配置的映射，找出作用域重叠的重复热键
; 冲突规则：
;   global 与任意非空作用域 → 冲突（作用域重叠）
;   exclude vs exclude → 冲突（保守策略，排除列表不同也可能重叠）
;   include vs include（进程列表有交集）→ 冲突
;   include vs global：include 非空即冲突
DetectHotkeyConflicts() {
    global HotkeyConflicts := []

    ; 收集所有已启用配置的映射，附带作用域信息
    hotkeyGroups := Map()
    modUsageB := Map()
    modUsageC := Map()

    for _, cfg in AllConfigs {
        if (!cfg["enabled"])
            continue
        if (cfg["mappings"].Length = 0)
            continue

        mode := cfg["processMode"]
        ; procKey 用于 include 模式下区分不同进程列表
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

            ; 收集修饰键路径使用情况（用于跨路径 B/C 冲突检测）
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

    ; 按热键分组比较，只在同组内检测作用域重叠
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

    ; 检测跨路径 B/C 修饰键冲突（同一修饰键在拦截和透传模式下同时使用）
    for modKey, bEntries in modUsageB {
        if !modUsageC.Has(modKey)
            continue
        cEntries := modUsageC[modKey]
        for _, bEntry in bEntries {
            for _, cEntry in cEntries {
                if ScopesOverlap(bEntry.mode, bEntry.procKey, cEntry.mode, cEntry.procKey) {
                    HotkeyConflicts.Push({
                        hotkey: modKey " (拦截/透传冲突)",
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

; 将 include 进程列表规范化为可比较的键：
; trim、去重、转小写、排序，然后以 | 连接
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

    ; 小数组场景下使用简单排序，避免引入额外依赖
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

; 判断两个 include 作用域是否有交集
IncludeScopesOverlap(procKey1, procKey2) {
    if (procKey1 = "" || procKey2 = "")
        return false

    list1 := StrSplit(procKey1, "|")
    list2 := StrSplit(procKey2, "|")

    ; 先将较短列表建集合，减少查找次数
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

; 判断 include 作用域与 exclude 作用域是否有交集
; 条件：include 中至少有一个进程不在 exclude 列表里
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

; 将 scopeKey（a.exe|b.exe）解析为集合 Map
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

; 判断两个作用域是否存在重叠
; 判定原则：两个作用域在任一进程下可能同时生效，则视为重叠
; include/include：有交集才重叠
; include/exclude：include 中存在未排除进程时重叠（global 与除空 include 外的任意作用域重叠）
ScopesOverlap(mode1, procKey1, mode2, procKey2) {
    ; include/include：有交集才重叠
    if (mode1 = "include" && mode2 = "include")
        return IncludeScopesOverlap(procKey1, procKey2)

    ; include/global：include 非空即与 global 重叠
    if (mode1 = "include" && mode2 = "global")
        return (procKey1 != "")
    if (mode2 = "include" && mode1 = "global")
        return (procKey2 != "")

    ; include/exclude：include 中存在未排除进程时重叠
    if (mode1 = "include" && mode2 = "exclude")
        return IncludeVsExcludeOverlap(procKey1, procKey2)
    if (mode2 = "include" && mode1 = "exclude")
        return IncludeVsExcludeOverlap(procKey2, procKey1)

    ; global 与 exclude/global 一律视为重叠
    if (mode1 = "global" || mode2 = "global")
        return true

    ; exclude/exclude：保守视为重叠
    return true
}

; 为单个配置注册所有热键
RegisterConfigHotkeys(cfg) {
    mappings := cfg["mappings"]
    if (mappings.Length = 0)
        return

    ; 创建该配置的进程匹配闭包
    checker := MakeProcessChecker(cfg)
    ; 保持引用防止 GC
    if (checker != "")
        AllProcessCheckers.Push(checker)

    useCustomHotIf := (checker != "")

    ; 第一遍：收集状态追踪式映射，按 sourceKey 分组
    for idx, mapping in mappings {
        modKey := mapping["ModifierKey"]
        if (modKey = "" || !mapping["PassthroughMod"])
            continue

        srcKey := mapping["SourceKey"]
        ; 分组键与注册去重键保持一致：
        ; - include/exclude: configName|sourceKey（按配置隔离）
        ; - global: |sourceKey（跨配置聚合，避免仅首个配置生效）
        groupPrefix := (cfg["processMode"] = "global") ? "" : cfg["name"]
        groupKey := groupPrefix "|" srcKey
        if !PassthroughHandlers.Has(groupKey)
            PassthroughHandlers[groupKey] := []

        PassthroughHandlers[groupKey].Push({
            modKey: modKey,
            targetKey: mapping["TargetKey"],
            holdRepeat: mapping["HoldRepeat"],
            repeatDelay: mapping["RepeatDelay"],
            repeatInterval: mapping["RepeatInterval"],
            idx: cfg["name"] "|" idx
        })
    }

    ; 第二遍：注册所有热键
    for idx, mapping in mappings {
        RegisterMapping(mapping, useCustomHotIf, checker, cfg["name"] "|" idx, cfg["name"])
    }
}

; 注册单个映射：根据 modKey 和 passthroughMod 分发到路径 A/B/C
RegisterMapping(mapping, useCustomHotIf, checker, uniqueIdx, configName) {
    modKey := mapping["ModifierKey"]

    if (useCustomHotIf)
        HotIf(checker)
    else
        HotIf()

    hkInfo := Map()
    hkInfo["checker"] := checker
    hkInfo["configName"] := configName

    if (modKey = "")
        RegisterPathA(mapping, hkInfo, uniqueIdx)
    else if (!mapping["PassthroughMod"])
        RegisterPathB(mapping, hkInfo, uniqueIdx, checker, configName)
    else
        RegisterPathC(mapping, hkInfo, checker, configName)

    ActiveHotkeys.Push(hkInfo)
}

; 路径 A：无修饰键，直接映射 sourceKey → targetKey
RegisterPathA(mapping, hkInfo, uniqueIdx) {
    sourceKey := mapping["SourceKey"]
    targetKey := mapping["TargetKey"]
    holdRepeat := mapping["HoldRepeat"]

    hkInfo["key"] := sourceKey

    if (holdRepeat) {
        downCb := HoldDownCallback.Bind(targetKey, mapping["RepeatDelay"], mapping["RepeatInterval"], uniqueIdx, sourceKey)
        upCb := HoldUpCallback.Bind(uniqueIdx)
        try {
            Hotkey(sourceKey, downCb, "On")
            Hotkey(sourceKey " Up", upCb, "On")
            hkInfo["keyUp"] := sourceKey " Up"
        } catch as e {
            HotkeyRegErrors.Push(sourceKey)
        }
    } else {
        try Hotkey(sourceKey, SendKeyCallback.Bind(targetKey), "On")
        catch as e
            HotkeyRegErrors.Push(sourceKey)
    }
}

; 路径 B：拦截式组合热键（modKey & sourceKey），修饰键不透传
RegisterPathB(mapping, hkInfo, uniqueIdx, checker, configName) {
    modKey := mapping["ModifierKey"]
    sourceKey := mapping["SourceKey"]
    targetKey := mapping["TargetKey"]
    holdRepeat := mapping["HoldRepeat"]
    comboKey := modKey " & " sourceKey

    hkInfo["key"] := comboKey

    if (holdRepeat) {
        downCb := HoldDownCallback.Bind(targetKey, mapping["RepeatDelay"], mapping["RepeatInterval"], uniqueIdx, sourceKey)
        upCb := HoldUpCallback.Bind(uniqueIdx)
        try {
            Hotkey(comboKey, downCb, "On")
            Hotkey(comboKey " Up", upCb, "On")
            hkInfo["keyUp"] := comboKey " Up"
        } catch as e {
            HotkeyRegErrors.Push(comboKey)
        }
    } else {
        try Hotkey(comboKey, SendKeyCallback.Bind(targetKey), "On")
        catch as e
            HotkeyRegErrors.Push(comboKey)
    }

    ; 注册修饰键恢复（同一 HotIf 条件下只注册一次）
    modRegKey := (checker != "" ? configName : "") "|" modKey
    if !InterceptModKeys.Has(modRegKey) {
        try {
            Hotkey(modKey, RestoreModKeyCallback.Bind(modKey), "On")
            modHkInfo := Map()
            modHkInfo["key"] := modKey
            modHkInfo["checker"] := checker
            modHkInfo["configName"] := configName
            ActiveHotkeys.Push(modHkInfo)
            InterceptModKeys[modRegKey] := true
        } catch as e {
            HotkeyRegErrors.Push(modKey)
        }
    }
}

; 路径 C：状态追踪式（修饰键透传），sourceKey 统一分发
RegisterPathC(mapping, hkInfo, checker, configName) {
    modKey := mapping["ModifierKey"]
    sourceKey := mapping["SourceKey"]
    sourceHotkey := SubStr(sourceKey, 1, 1) = "*" ? sourceKey : "*" sourceKey
    srcRegKey := (checker != "" ? configName : "") "|" sourceKey
    groupKey := srcRegKey

    hkInfo["key"] := sourceHotkey

    if !PassthroughSourceRegistered.Has(srcRegKey) {
        try {
            Hotkey(sourceHotkey, PassthroughSourceHandler.Bind(groupKey), "On")
            PassthroughSourceRegistered[srcRegKey] := true
        } catch as e {
            HotkeyRegErrors.Push(sourceHotkey)
        }
    }

    ; 注册修饰键状态追踪（同一 HotIf 条件下只注册一次）
    modRegKey := (checker != "" ? configName : "") "|" modKey
    if !PassthroughModKeys.Has(modRegKey) {
        SetupPassthroughModKey(modKey, checker, configName)
        PassthroughModKeys[modRegKey] := true
    }
}

; 设置状态追踪式修饰键的按下/松开监控
SetupPassthroughModKey(modKey, checker := "", configName := "") {
    ComboFiredState[modKey] := false

    downCb := PassthroughModDown.Bind(modKey)
    upCb := PassthroughModUp.Bind(modKey)
    try {
        Hotkey("~" modKey, downCb, "On")
        Hotkey("~" modKey " Up", upCb, "On")
    } catch as e {
        HotkeyRegErrors.Push("~" modKey)
    }

    modHkInfo := Map()
    modHkInfo["key"] := "~" modKey
    modHkInfo["keyUp"] := "~" modKey " Up"
    modHkInfo["checker"] := checker
    modHkInfo["configName"] := configName
    ActiveHotkeys.Push(modHkInfo)
}

; 清理状态追踪式修饰键的监控
CleanupPassthroughModKeys() {
    ; 通过 ActiveHotkeys 中记录的 checker 来正确卸载
    ; （在 UnregisterAllHotkeys 的主循环中统一处理）
    ; 这里只重置状态
    global PassthroughModKeys := Map()
}

; 修饰键按下：初始化组合触发状态
PassthroughModDown(modKey, *) {
    ComboFiredState[modKey] := false
}

; 修饰键松开：如果触发过组合，尝试抑制副作用
PassthroughModUp(modKey, *) {
    if (ComboFiredState.Has(modKey) && ComboFiredState[modKey]) {
        ComboFiredState[modKey] := false
        ; ~ 前缀已经让物理事件通过，无法阻止
        ; 对于 RButton，松开可能触发右键菜单，用 Escape 关闭
        if (modKey = "RButton")
            SetTimer(DismissContextMenu, -CONTEXT_MENU_DISMISS_DELAY)
        return
    }
    ComboFiredState[modKey] := false
}

; 延迟关闭右键菜单（给系统一点时间弹出菜单后再关闭）
DismissContextMenu(*) {
    Send("{Escape}")
}

; ============================================================================
; 路径 A/B 回调
; ============================================================================

SendKeyCallback(targetKey, *) {
    Send(KeyToSendFormat(targetKey))
}

HoldDownCallback(targetKey, repeatDelay, repeatInterval, idx, sourceKey, *) {
    ; 防御性清理：如果已有定时器运行（防止重入导致孤立定时器）
    if HoldTimers.Has(idx) {
        if (HoldTimers[idx].HasProp("fn"))
            SetTimer(HoldTimers[idx].fn, 0)
        if (HoldTimers[idx].HasProp("startFn"))
            SetTimer(HoldTimers[idx].startFn, 0)
        HoldTimers[idx].active := false
    }

    sendKey := KeyToSendFormat(targetKey)
    Send(sendKey)

    timerFn := RepeatTimerCallback.Bind(sendKey, sourceKey, idx)
    startFn := StartRepeat.Bind(idx, timerFn, repeatInterval)
    HoldTimers[idx] := { fn: timerFn, startFn: startFn, interval: repeatInterval, active: true }
    SetTimer(startFn, -repeatDelay)
}

StartRepeat(idx, timerFn, interval, *) {
    if (HoldTimers.Has(idx) && HoldTimers[idx].active)
        SetTimer(timerFn, interval)
}

RepeatTimerCallback(sendKey, sourceKey, idx, modKey := "", *) {
    ; 路径 C：检查修饰键是否仍被按住
    if (modKey != "" && !GetKeyState(modKey, "P")) {
        if HoldTimers.Has(idx) {
            if (HoldTimers[idx].HasProp("fn"))
                SetTimer(HoldTimers[idx].fn, 0)
            HoldTimers[idx].active := false
            HoldTimers.Delete(idx)
        }
        return
    }
    ; 安全检查：如果源按键已松开（非滚轮键），自动停止定时器
    baseKey := RegExReplace(sourceKey, "^[+!#^]+", "")
    if (baseKey != "" && !RegExMatch(baseKey, "^Wheel") && !GetKeyState(baseKey, "P")) {
        if HoldTimers.Has(idx) {
            if (HoldTimers[idx].HasProp("fn"))
                SetTimer(HoldTimers[idx].fn, 0)
            HoldTimers[idx].active := false
            HoldTimers.Delete(idx)
        }
        return
    }
    Send(sendKey)
}

HoldUpCallback(idx, *) {
    if HoldTimers.Has(idx) {
        if (HoldTimers[idx].HasProp("fn"))
            SetTimer(HoldTimers[idx].fn, 0)
        if (HoldTimers[idx].HasProp("startFn"))
            SetTimer(HoldTimers[idx].startFn, 0)
        HoldTimers[idx].active := false
        HoldTimers.Delete(idx)
    }
}

RestoreModKeyCallback(modKey, *) {
    Send(KeyToSendFormat(modKey))
}

; ============================================================================
; 路径 C 回调（状态追踪式）
; ============================================================================

; sourceKey 的统一处理器：检查所有关联的修饰键
; groupKey 格式为 "configName|sourceKey"
PassthroughSourceHandler(groupKey, *) {
    if !PassthroughHandlers.Has(groupKey) {
        ; 没有关联的组合映射，从 groupKey 提取 sourceKey 转发
        parts := StrSplit(groupKey, "|",, 2)
        sourceKey := parts.Length >= 2 ? parts[2] : groupKey
        Send(KeyToSendFormat(sourceKey))
        return
    }

    handlers := PassthroughHandlers[groupKey]
    for _, h in handlers {
        if GetKeyState(h.modKey, "P") {
            ; 修饰键按住，触发组合
            ComboFiredState[h.modKey] := true

            if (h.holdRepeat) {
                _parts := StrSplit(groupKey, "|",, 2)
                _srcKey := _parts.Length >= 2 ? _parts[2] : ""
                sendKey := KeyToSendFormat(h.targetKey)
                Send(sendKey)
                timerFn := RepeatTimerCallback.Bind(sendKey, _srcKey, h.idx, h.modKey)
                startFn := StartRepeat.Bind(h.idx, timerFn, h.repeatInterval)
                HoldTimers[h.idx] := { fn: timerFn, startFn: startFn, interval: h.repeatInterval, active: true }
                SetTimer(startFn, -h.repeatDelay)
            } else {
                Send(KeyToSendFormat(h.targetKey))
            }
            return
        }
    }

    ; 没有任何修饰键按住，从 groupKey 提取 sourceKey 转发
    parts := StrSplit(groupKey, "|",, 2)
    sourceKey := parts.Length >= 2 ? parts[2] : groupKey
    Send(KeyToSendFormat(sourceKey))
}






