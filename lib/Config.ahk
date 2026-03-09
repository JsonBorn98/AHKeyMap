; ============================================================================
; AHKeyMap - 配置管理模块
; 负责加载、保存、管理配置文件
; ============================================================================

; 声明跨文件使用的全局变量
global APP_NAME
global SCRIPT_DIR
global CONFIG_DIR
global STATE_FILE
global AllConfigs
global CurrentConfigName
global CurrentConfigFile
global CurrentProcessMode
global CurrentProcess
global CurrentProcessList
global CurrentExcludeProcess
global CurrentExcludeProcessList
global CurrentConfigEnabled
global Mappings
global ConfigDDL
global EnabledCB
global ProcessText
global StatusText
global StatusDetailLink
global StatusHasWarning
global MappingLV
global HotkeyConflicts
global HotkeyRegErrors
global DEFAULT_REPEAT_DELAY
global DEFAULT_REPEAT_INTERVAL

; ============================================================================
; 配置管理函数
; ============================================================================

; 获取所有配置文件名（不含扩展名）
GetConfigList() {
    configs := []
    try {
        loop files CONFIG_DIR "\*.ini" {
            name := RegExReplace(A_LoopFileName, "\.ini$", "")
            if (name != "_state")
                configs.Push(name)
        }
    }
    return configs
}

; 加载所有配置到 AllConfigs（启动时调用一次）
LoadAllConfigs() {
    global AllConfigs := []
    configs := GetConfigList()
    for _, name in configs {
        cfg := LoadConfigData(name)
        if (cfg != "")
            AllConfigs.Push(cfg)
    }
}

; 从 INI 文件加载一个配置的完整数据，返回 Map 对象
LoadConfigData(configName) {
    configFile := CONFIG_DIR "\" configName ".ini"
    if !FileExist(configFile)
        return ""

    cfg := Map()
    cfg["name"] := configName
    cfg["file"] := configFile

    ; 读取 Meta - 进程模式（向后兼容）
    processMode := IniRead(configFile, "Meta", "ProcessMode", "")
    process := IniRead(configFile, "Meta", "Process", "")
    excludeProcess := IniRead(configFile, "Meta", "ExcludeProcess", "")

    ; 向后兼容：旧配置无 ProcessMode 时自动推断
    if (processMode = "") {
        if (process != "")
            processMode := "include"
        else
            processMode := "global"
    }

    cfg["processMode"] := processMode
    cfg["process"] := process
    cfg["processList"] := ParseProcessList(process)
    cfg["excludeProcess"] := excludeProcess
    cfg["excludeProcessList"] := ParseProcessList(excludeProcess)

    ; 读取启用状态（从 _state.ini）
    enabledVal := "1"
    if FileExist(STATE_FILE)
        enabledVal := IniRead(STATE_FILE, "EnabledConfigs", configName, "1")
    cfg["enabled"] := (enabledVal = "1")

    ; 读取映射
    mappings := []
    idx := 1
    loop {
        section := "Mapping" idx
        sourceKey := IniRead(configFile, section, "SourceKey", "")
        if (sourceKey = "")
            break

        mapping := Map()
        mapping["ModifierKey"] := IniRead(configFile, section, "ModifierKey", "")
        mapping["SourceKey"] := sourceKey
        mapping["TargetKey"] := IniRead(configFile, section, "TargetKey", "")
        mapping["HoldRepeat"] := Integer(IniRead(configFile, section, "HoldRepeat", "0"))
        mapping["RepeatDelay"] := Integer(IniRead(configFile, section, "RepeatDelay", String(DEFAULT_REPEAT_DELAY)))
        mapping["RepeatInterval"] := Integer(IniRead(configFile, section, "RepeatInterval", String(DEFAULT_REPEAT_INTERVAL)))
        mapping["PassthroughMod"] := Integer(IniRead(configFile, section, "PassthroughMod", "0"))
        mappings.Push(mapping)
        idx++
    }
    cfg["mappings"] := mappings

    return cfg
}

; 在 AllConfigs 中查找指定名称的配置，返回索引（0=未找到）
FindConfigIndex(configName) {
    for i, cfg in AllConfigs {
        if (cfg["name"] = configName)
            return i
    }
    return 0
}

; 同步当前 GUI 编辑状态到 AllConfigs
SyncCurrentToAllConfigs() {
    if (CurrentConfigName = "")
        return
    idx := FindConfigIndex(CurrentConfigName)
    if (idx = 0)
        return
    cfg := AllConfigs[idx]
    cfg["processMode"] := CurrentProcessMode
    cfg["process"] := CurrentProcess
    cfg["processList"] := CurrentProcessList
    cfg["excludeProcess"] := CurrentExcludeProcess
    cfg["excludeProcessList"] := CurrentExcludeProcessList
    cfg["enabled"] := CurrentConfigEnabled
    cfg["mappings"] := Mappings
}

; 刷新配置下拉列表（仅 GUI 显示，不影响热键）
RefreshConfigList(selectName := "") {
    configs := GetConfigList()
    items := []
    selectIdx := 0
    for i, name in configs {
        items.Push(name)
        if (name = selectName)
            selectIdx := i
    }

    ConfigDDL.Delete()
    if (items.Length > 0) {
        ConfigDDL.Add(items)
        if (selectIdx > 0)
            ConfigDDL.Choose(selectIdx)
        else
            ConfigDDL.Choose(1)
        OnConfigSelect(ConfigDDL, "")
    } else {
        global CurrentConfigName := ""
        global CurrentConfigFile := ""
        global CurrentProcessMode := "global"
        global CurrentProcess := ""
        global CurrentProcessList := []
        global CurrentExcludeProcess := ""
        global CurrentExcludeProcessList := []
        global CurrentConfigEnabled := true
        ProcessText.Value := "作用域: 无配置"
        EnabledCB.Value := 0
        EnabledCB.Enabled := false
        global Mappings := []
        RefreshMappingLV()
    }
    UpdateStatusText()
}

; 解析进程字符串为数组
ParseProcessList(procStr) {
    result := []
    if (procStr = "")
        return result
    loop parse procStr, "|" {
        trimmed := Trim(A_LoopField)
        if (trimmed != "")
            result.Push(trimmed)
    }
    return result
}

; 格式化进程作用域为显示文本（接受已解析的数组）
FormatProcessDisplay(processMode, processList, excludeProcessList) {
    if (processMode = "include") {
        if (processList.Length = 0)
            return "作用域: 全局"
        if (processList.Length = 1)
            return "作用域: 仅 " processList[1]
        return "作用域: 仅 " processList[1] " 等" processList.Length "个"
    } else if (processMode = "exclude") {
        if (excludeProcessList.Length = 0)
            return "作用域: 全局"
        if (excludeProcessList.Length = 1)
            return "作用域: 排除 " excludeProcessList[1]
        return "作用域: 排除 " excludeProcessList[1] " 等" excludeProcessList.Length "个"
    }
    return "作用域: 全局"
}

; 更新状态栏文本
UpdateStatusText() {
    enabledCount := 0
    totalCount := AllConfigs.Length
    for _, cfg in AllConfigs {
        if (cfg["enabled"])
            enabledCount++
    }

    statusStr := "已启用 " enabledCount "/" totalCount " 个配置"
    hasWarning := false
    if (HotkeyConflicts.Length > 0) {
        statusStr .= "  ⚠ " HotkeyConflicts.Length " 个热键冲突"
        hasWarning := true
    }
    if (HotkeyRegErrors.Length > 0) {
        statusStr .= "  ⚠ " HotkeyRegErrors.Length " 个热键注册失败"
        hasWarning := true
    }

    ; 有警告时：状态文字变橙色，并显示右侧详情入口
    global StatusHasWarning := hasWarning
    if (hasWarning) {
        StatusText.SetFont("cE07B00")
        StatusDetailLink.Opt("-Hidden")
    } else {
        StatusText.SetFont("cGray")
        StatusDetailLink.Opt("+Hidden")
        SetStatusDetailHover(false)
    }
    StatusText.Value := statusStr
}

; 加载指定配置到 GUI 编辑区域（不影响热键注册）
LoadConfigToGui(configName) {
    idx := FindConfigIndex(configName)
    if (idx = 0)
        return

    global CurrentConfigName := configName
    global CurrentConfigFile := CONFIG_DIR "\" configName ".ini"

    cfg := AllConfigs[idx]
    global CurrentProcessMode := cfg["processMode"]
    global CurrentProcess := cfg["process"]
    global CurrentProcessList := cfg["processList"]
    global CurrentExcludeProcess := cfg["excludeProcess"]
    global CurrentExcludeProcessList := cfg["excludeProcessList"]
    global CurrentConfigEnabled := cfg["enabled"]

    global Mappings := []
    for _, m in cfg["mappings"] {
        newM := Map()
        for k, v in m
            newM[k] := v
        Mappings.Push(newM)
    }

    ProcessText.Value := FormatProcessDisplay(CurrentProcessMode, CurrentProcessList, CurrentExcludeProcessList)
    EnabledCB.Value := CurrentConfigEnabled
    EnabledCB.Enabled := true

    RefreshMappingLV()

    ; 保存最后查看的配置
    try IniWrite(configName, STATE_FILE, "State", "LastConfig")
}

; 保存当前配置到文件（原子写入：先写临时文件，成功后替换原文件）
SaveConfig() {
    if (CurrentConfigName = "" || CurrentConfigFile = "")
        return

    tempFile := CurrentConfigFile ".tmp"

    ; 第一步：将全部内容写入临时文件（按节批量写入）
    try {
        if FileExist(tempFile)
            FileDelete(tempFile)

        metaPairs := "Name=" CurrentConfigName
        metaPairs .= "`nProcessMode=" CurrentProcessMode
        metaPairs .= "`nProcess=" CurrentProcess
        metaPairs .= "`nExcludeProcess=" CurrentExcludeProcess
        IniWrite(metaPairs, tempFile, "Meta")

        for idx, mapping in Mappings {
            pairs := "ModifierKey=" mapping["ModifierKey"]
            pairs .= "`nSourceKey=" mapping["SourceKey"]
            pairs .= "`nTargetKey=" mapping["TargetKey"]
            pairs .= "`nHoldRepeat=" mapping["HoldRepeat"]
            pairs .= "`nRepeatDelay=" mapping["RepeatDelay"]
            pairs .= "`nRepeatInterval=" mapping["RepeatInterval"]
            pairs .= "`nPassthroughMod=" mapping["PassthroughMod"]
            IniWrite(pairs, tempFile, "Mapping" idx)
        }
    } catch as e {
        ; 写临时文件失败，原文件未动，清理残留 tmp
        try FileDelete(tempFile)
        MsgBox("保存配置失败：" e.Message "`n文件：" CurrentConfigFile, APP_NAME, "IconX")
        return
    }

    ; 第二步：用临时文件覆盖原文件（FileMove 覆盖模式，避免先删后移的数据丢失风险）
    try {
        FileMove(tempFile, CurrentConfigFile, 1)
    } catch as e {
        try FileDelete(tempFile)
        MsgBox("保存配置失败（替换阶段）：" e.Message "`n文件：" CurrentConfigFile, APP_NAME, "IconX")
        return
    }

    ; 同步到 AllConfigs 并保存启用状态
    SyncCurrentToAllConfigs()
    SaveEnabledStates()
}

; 保存所有配置的启用状态到 _state.ini（原子写入）
SaveEnabledStates() {
    tempFile := STATE_FILE ".tmp"
    try {
        if FileExist(tempFile)
            FileDelete(tempFile)

        ; 保留 [State] 节
        lastConfig := ""
        if FileExist(STATE_FILE)
            lastConfig := IniRead(STATE_FILE, "State", "LastConfig", "")
        if (lastConfig != "")
            IniWrite(lastConfig, tempFile, "State", "LastConfig")

        for _, cfg in AllConfigs
            IniWrite(cfg["enabled"] ? "1" : "0", tempFile, "EnabledConfigs", cfg["name"])

        FileMove(tempFile, STATE_FILE, 1)
    } catch as e {
        try FileDelete(tempFile)
        MsgBox("保存启用状态失败：" e.Message, APP_NAME, "IconX")
    }
}

; 刷新 ListView 显示
RefreshMappingLV() {
    MappingLV.Delete()
    for idx, mapping in Mappings {
        holdText := mapping["HoldRepeat"] ? "是" : "否"
        modDisplay := mapping["ModifierKey"] != "" ? KeyToDisplay(mapping["ModifierKey"]) : ""
        ptText := ""
        if (mapping["ModifierKey"] != "")
            ptText := mapping["PassthroughMod"] ? "保留" : "拦截"
        delayText := mapping["HoldRepeat"] ? mapping["RepeatDelay"] : ""
        intervalText := mapping["HoldRepeat"] ? mapping["RepeatInterval"] : ""
        MappingLV.Add(""
            , idx
            , modDisplay
            , KeyToDisplay(mapping["SourceKey"])
            , KeyToDisplay(mapping["TargetKey"])
            , holdText
            , ptText
            , delayText
            , intervalText)
    }
    ; 自动调整列宽
    loop 8
        MappingLV.ModifyCol(A_Index, "AutoHdr")
}

