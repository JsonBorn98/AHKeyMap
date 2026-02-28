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
        return (*) => CheckIncludeMatch(procList)
    } else if (mode = "exclude") {
        exclList := cfg["excludeProcessList"]
        return (*) => CheckExcludeMatch(exclList)
    }
    ; global 模式不需要 HotIf 条件
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
    try {
        fgProc := WinGetProcessName("A")
        for procName in exclList {
            if (fgProc = procName)
                return false
        }
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


; 检测热键冲突：扫描所有已启用配置的映射，找出作用域重叠的重复热键
; 冲突规则：
;   global vs global/exclude → 冲突（作用域重叠）
;   exclude vs exclude → 冲突（保守策略，排除列表不同也可能重叠）
;   include vs include（相同进程列表）→ 冲突
;   include vs 其他 → 不冲突（include 优先级最高，独立生效）
DetectHotkeyConflicts() {
    global HotkeyConflicts := []

    ; 收集所有已启用配置的映射，附带作用域信息
    allEntries := []  ; Array of {hotkey, configName, mappingIdx, mode, procKey}

    for _, cfg in AllConfigs {
        if (!cfg["enabled"])
            continue
        if (cfg["mappings"].Length = 0)
            continue

        mode := cfg["processMode"]
        ; procKey 用于 include 模式下区分不同进程列表
        if (mode = "include")
            procKey := cfg["process"]
        else
            procKey := ""

        for idx, mapping in cfg["mappings"] {
            ; 构建热键字符串（与注册路径一致）
            modKey := mapping["ModifierKey"]
            sourceKey := mapping["SourceKey"]
            if (modKey = "")
                hkStr := sourceKey
            else if (!mapping["PassthroughMod"])
                hkStr := modKey " & " sourceKey
            else
                hkStr := "~" modKey "+" sourceKey

            allEntries.Push({
                hotkey: hkStr,
                configName: cfg["name"],
                mappingIdx: idx,
                mode: mode,
                procKey: procKey
            })
        }
    }

    ; 两两比较，检测作用域重叠的相同热键
    count := allEntries.Length
    i := 1
    while (i <= count) {
        j := i + 1
        while (j <= count) {
            a := allEntries[i]
            b := allEntries[j]
            if (a.hotkey = b.hotkey && ScopesOverlap(a.mode, a.procKey, b.mode, b.procKey)) {
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

; 判断两个作用域是否存在重叠
; include 与非 include 不重叠（include 优先级最高，独立匹配）
; include 与 include 仅在进程列表相同时重叠
; global/exclude 之间总是重叠（保守策略）
ScopesOverlap(mode1, procKey1, mode2, procKey2) {
    ; include 与非 include → 不重叠
    if (mode1 = "include" && mode2 != "include")
        return false
    if (mode2 = "include" && mode1 != "include")
        return false
    ; 两个都是 include → 进程列表相同才重叠
    if (mode1 = "include" && mode2 = "include")
        return (procKey1 = procKey2)
    ; global/exclude 之间 → 总是重叠
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
        ; 使用配置名+sourceKey 作为键，避免跨配置冲突
        groupKey := cfg["name"] "|" srcKey
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
        }
    } else {
        try Hotkey(sourceKey, SendKeyCallback.Bind(targetKey), "On")
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
        }
    } else {
        try Hotkey(comboKey, SendKeyCallback.Bind(targetKey), "On")
    }

    ; 注册修饰键恢复（同一 HotIf 条件下只注册一次）
    modRegKey := (checker != "" ? configName : "") "|" modKey
    if !InterceptModKeys.Has(modRegKey) {
        try {
            Hotkey(modKey, RestoreModKeyCallback.Bind(modKey), "On")
            modHkInfo := Map()
            modHkInfo["key"] := modKey
            modHkInfo["checker"] := checker
            ActiveHotkeys.Push(modHkInfo)
            InterceptModKeys[modRegKey] := true
        }
    }
}

; 路径 C：状态追踪式（修饰键透传），sourceKey 统一分发
RegisterPathC(mapping, hkInfo, checker, configName) {
    modKey := mapping["ModifierKey"]
    sourceKey := mapping["SourceKey"]
    groupKey := configName "|" sourceKey
    srcRegKey := (checker != "" ? configName : "") "|" sourceKey

    hkInfo["key"] := sourceKey

    if !PassthroughSourceRegistered.Has(srcRegKey) {
        try Hotkey(sourceKey, PassthroughSourceHandler.Bind(groupKey), "On")
        PassthroughSourceRegistered[srcRegKey] := true
    }

    ; 注册修饰键状态追踪（同一 HotIf 条件下只注册一次）
    modRegKey := (checker != "" ? configName : "") "|" modKey
    if !PassthroughModKeys.Has(modRegKey) {
        SetupPassthroughModKey(modKey, checker)
        PassthroughModKeys[modRegKey] := true
    }
}

; 设置状态追踪式修饰键的按下/松开监控
SetupPassthroughModKey(modKey, checker := "") {
    ComboFiredState[modKey] := false

    downCb := PassthroughModDown.Bind(modKey)
    upCb := PassthroughModUp.Bind(modKey)
    try {
        Hotkey("~" modKey, downCb, "On")
        Hotkey("~" modKey " Up", upCb, "On")
    }

    ; 记录用于卸载
    modHkInfo := Map()
    modHkInfo["key"] := "~" modKey
    modHkInfo["keyUp"] := "~" modKey " Up"
    modHkInfo["checker"] := checker
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

RepeatTimerCallback(sendKey, sourceKey, idx, *) {
    ; 安全检查：如果源按键已松开（非滚轮键），自动停止定时器
    ; 去除修饰键前缀（^ + ! #），GetKeyState 只接受纯按键名
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
                ; 长按连续触发
                ; 提取 sourceKey（从 groupKey "configName|sourceKey"）
                _parts := StrSplit(groupKey, "|",, 2)
                _srcKey := _parts.Length >= 2 ? _parts[2] : ""
                sendKey := KeyToSendFormat(h.targetKey)
                Send(sendKey)
                timerFn := RepeatTimerCallback.Bind(sendKey, _srcKey, h.idx)
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
