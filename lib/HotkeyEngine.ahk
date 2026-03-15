; ============================================================================
; AHKeyMap - 热键引擎模块
; 负责热键注册、回调处理、长按连续触发等核心功能
; ============================================================================

; 声明跨文件使用的全局变量
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

; 向数组追加唯一值
AddUniqueArrayValue(arr, value) {
    for _, existingValue in arr {
        if (existingValue = value)
            return
    }
    arr.Push(value)
}

; 路径 C 的 sourceKey 仅在可监听 KeyUp 时注册 Up 热键
SupportsKeyUpHotkey(hotkeyName) {
    baseKey := RegExReplace(hotkeyName, "^[~*$+!#^]+", "")
    return !RegExMatch(baseKey, "^Wheel")
}

; 卸载所有当前热键
UnregisterAllHotkeys() {
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
    global InterceptModKeys := Map()
    global HoldTimers := Map()
    global AllProcessCheckers := []
    global HotkeyRegErrors := []
    global PathCMappingByModSource := Map()
    global PathCModSessions := Map()
    global PathCModsUsed := Map()
    global PathCSourceKeysUsed := Map()
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

    ; 为所有路径 C 映射注册统一的修饰键与源键路由热键
    RegisterAllPathCHotkeys()

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

    ; 创建该配置的进程匹配闭包（供路径 A/B 使用；路径 C 将在回调中显式检查作用域）
    checker := MakeProcessChecker(cfg)
    ; 保持引用防止 GC
    if (checker != "")
        AllProcessCheckers.Push(checker)

    useCustomHotIf := (checker != "")

    ; 注册当前配置下的所有映射（路径 A/B 直接注册热键；路径 C 仅构建映射表）
    for idx, mapping in mappings {
        RegisterMapping(mapping, useCustomHotIf, checker, cfg["name"] "|" idx, cfg["name"])
    }
}

; 注册单个映射：根据 modKey 和 passthroughMod 分发到路径 A/B/C
RegisterMapping(mapping, useCustomHotIf, checker, uniqueIdx, configName) {
    modKey := mapping["ModifierKey"]

    ; 路径 A：无修饰键，直接注册热键
    if (modKey = "") {
        if (useCustomHotIf)
            HotIf(checker)
        else
            HotIf()
        hkInfo := Map()
        hkInfo["checker"] := checker
        hkInfo["configName"] := configName
        RegisterPathA(mapping, hkInfo, uniqueIdx)
        ActiveHotkeys.Push(hkInfo)
        return
    }

    ; 路径 B：拦截式组合热键（modKey & sourceKey），修饰键不透传
    if (!mapping["PassthroughMod"]) {
        if (useCustomHotIf)
            HotIf(checker)
        else
            HotIf()
        hkInfo := Map()
        hkInfo["checker"] := checker
        hkInfo["configName"] := configName
        RegisterPathB(mapping, hkInfo, uniqueIdx, checker, configName)
        ActiveHotkeys.Push(hkInfo)
        return
    }

    ; 路径 C：状态化透传，统一由 Path C 引擎处理，不在注册层直接绑定目标回调
    HotIf()
    RegisterPathCMapping(mapping, uniqueIdx, configName, checker)
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

; 路径 C：仅构建映射表，具体行为由 Path C 引擎统一处理
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
; 路径 A/B 回调
; ============================================================================

SendKeyCallback(targetKey, *) {
    Send(KeyToSendFormat(targetKey))
}

HoldDownCallback(targetKey, repeatDelay, repeatInterval, idx, sourceKey, *) {
    ; 防御性清理：如果已有定时器运行（防止重入导致孤立定时器）
    StopHoldTimer(idx)

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
    ; 路径 C：检查修饰键是否仍被按住
    if (modKey != "" && !GetKeyState(modKey, "P")) {
        StopHoldTimer(idx)
        return
    }
    ; 安全检查：如果源按键已松开（非滚轮键），自动停止定时器
    baseKey := RegExReplace(sourceKey, "^[+!#^]+", "")
    if (baseKey != "" && !RegExMatch(baseKey, "^Wheel") && !GetKeyState(baseKey, "P")) {
        StopHoldTimer(idx)
        return
    }
    Send(sendKey)
}

HoldUpCallback(idx, *) {
    StopHoldTimer(idx)
}

RestoreModKeyCallback(modKey, *) {
    Send(KeyToSendFormat(modKey))
}

; ============================================================================
; 路径 C 引擎（显式状态机 + 统一事件路由）
; ============================================================================

; 注册所有 Path C 所需的修饰键与源键热键（在所有配置处理完成后调用）
RegisterAllPathCHotkeys() {
    global PathCModsUsed, PathCSourceKeysUsed, ActiveHotkeys, HotkeyRegErrors

    ; 修饰键：键盘修饰键/鼠标键通用，全部使用 "~modKey" / "~modKey Up" 透传物理事件
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

        modHkInfo := Map()
        modHkInfo["key"] := downHk
        modHkInfo["keyUp"] := upHk
        modHkInfo["checker"] := ""
        modHkInfo["configName"] := ""
        ActiveHotkeys.Push(modHkInfo)
    }

    ; 源键：统一监听，实际触发逻辑在 Path C 引擎中判定
    for sourceKey, _ in PathCSourceKeysUsed {
        if (sourceKey = "")
            continue

        sourceHotkey := SubStr(sourceKey, 1, 1) = "*" ? sourceKey : "*" sourceKey

        ; KeyDown
        hkInfo := Map()
        hkInfo["checker"] := ""
        hkInfo["configName"] := ""
        hkInfo["key"] := sourceHotkey

        try {
            HotIf()
            Hotkey(sourceHotkey, PathC_SourceDownCallback.Bind(sourceKey), "On")
        } catch as e {
            HotkeyRegErrors.Push(sourceHotkey)
        }

        ; KeyUp（仅对支持 Up 热键的源键注册）
        if (SupportsKeyUpHotkey(sourceHotkey)) {
            srcUpHotkey := sourceHotkey " Up"
            try {
                HotIf()
                Hotkey(srcUpHotkey, PathC_SourceUpCallback.Bind(sourceKey), "On")
                hkInfo["keyUp"] := srcUpHotkey
            } catch as e {
                HotkeyRegErrors.Push(srcUpHotkey)
            }
        }
        ActiveHotkeys.Push(hkInfo)
    }

    HotIf()
}

; 获取或初始化指定修饰键的会话状态
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

; 结束指定修饰键的会话：停止所有重复触发并重置状态
PathC_EndSession(modKey) {
    global PathCModSessions, HoldTimers
    if !PathCModSessions.Has(modKey)
        return

    session := PathCModSessions[modKey]

    ; 停止所有与该修饰键关联的重复定时器
    for mappingId, _ in session.repeatMappings {
        StopHoldTimer(mappingId)
    }

    session.repeatMappings := Map()
    session.activeSources := Map()
    session.state := "Idle"
    session.isGesture := false
}

; 判断映射在当前前台窗口下是否生效（基于配置生成的 checker 闭包）
PathC_IsMappingActive(mapping) {
    if (mapping.HasOwnProp("checker") && mapping.checker != "") {
        try
            return mapping.checker.Call()
        catch
            return false
    }
    return true
}

; 启动路径 C 的长按重复触发
PathC_StartRepeat(mapping, modKey, sourceKey) {
    global HoldTimers

    idx := mapping.id
    sendKey := KeyToSendFormat(mapping.targetKey)

    ; 防御性清理：如果已有定时器运行（防止重入导致孤立定时器）
    StopHoldTimer(idx)

    Send(sendKey)

    timerFn := RepeatTimerCallback.Bind(sendKey, sourceKey, idx, modKey)
    startFn := StartRepeat.Bind(idx, timerFn, mapping.repeatInterval)
    HoldTimers[idx] := { fn: timerFn, startFn: startFn, interval: mapping.repeatInterval, active: true }
    SetTimer(startFn, -mapping.repeatDelay)
}

; Path C 修饰键按下回调（统一入口）
PathC_ModDownCallback(modKey, *) {
    session := PathC_GetSession(modKey)

    ; 若上一次会话尚未完结，先强制结束
    if (session.state != "Idle")
        PathC_EndSession(modKey)

    session := PathC_GetSession(modKey)
    session.state := "HeldNoCombo"
    session.isGesture := false
    session.activeSources := Map()
    session.repeatMappings := Map()
}

; Path C 修饰键松开回调（统一入口）
PathC_ModUpCallback(modKey, *) {
    session := PathC_GetSession(modKey)
    if (session.state = "Idle") {
        return
    }

    isGesture := session.isGesture

    ; 对于 RButton，只在“已触发 Path C 组合”的手势会话中尝试关闭可能弹出的右键菜单；
    ; 通过发送 Escape 实现，保留浏览器等工具对 RButton 手势的处理能力。
    if (modKey = "RButton" && isGesture) {
        SetTimer(PathC_DismissContextMenu, -CONTEXT_MENU_DISMISS_DELAY)
    }

    PathC_EndSession(modKey)
}

PathC_DismissContextMenu(*) {
    Send("{Escape}")
}

; Path C 源键按下回调（统一入口）
PathC_SourceDownCallback(sourceKey, *) {
    global PathCMappingByModSource, PathCModSessions

    handled := false

    ; 遍历所有当前活跃的修饰键会话
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

            ; 标记本次会话为手势会话
            session.state := "GestureActive"
            session.isGesture := true

            if (mapping.holdRepeat) {
                PathC_StartRepeat(mapping, modKey, sourceKey)
                session.repeatMappings[mapping.id] := true

                if !session.activeSources.Has(sourceKey)
                    session.activeSources[sourceKey] := []
                session.activeSources[sourceKey].Push(mapping.id)
            } else {
                Send(KeyToSendFormat(mapping.targetKey))
            }

            handled := true
            break
        }

        if (handled)
            break
    }

    if (!handled) {
        ; 未命中任何 Path C 映射，回退为原始按键
        Send(KeyToSendFormat(sourceKey))
    }
}

; Path C 源键松开回调（统一入口，仅对支持 Up 的源键生效）
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
