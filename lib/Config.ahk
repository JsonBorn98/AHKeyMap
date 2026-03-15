; ============================================================================
; AHKeyMap - Config management module
; Load, save and manage config INI files
; ============================================================================

; Globals shared across modules
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
; Config management functions
; ============================================================================

; Get all config file names (without extension)
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

; Load all configs into AllConfigs (called at startup)
LoadAllConfigs() {
    AllConfigs.Length := 0
    configs := GetConfigList()
    for _, name in configs {
        cfg := LoadConfigData(name)
        if (cfg != "")
            AllConfigs.Push(cfg)
    }
}

; Load full config data from INI file, return as Map
LoadConfigData(configName) {
    configFile := CONFIG_DIR "\" configName ".ini"
    if !FileExist(configFile)
        return ""

    cfg := Map()
    cfg["name"] := configName
    cfg["file"] := configFile

    ; Read Meta section - process mode (with backwards compatibility)
    processMode := IniRead(configFile, "Meta", "ProcessMode", "")
    process := IniRead(configFile, "Meta", "Process", "")
    excludeProcess := IniRead(configFile, "Meta", "ExcludeProcess", "")

    ; Backwards compatibility: infer ProcessMode when missing
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

    ; Read enabled state from _state.ini
    enabledVal := "1"
    if FileExist(STATE_FILE)
        enabledVal := IniRead(STATE_FILE, "EnabledConfigs", configName, "1")
    cfg["enabled"] := (enabledVal = "1")

    ; Read mappings
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

; Find config index by name in AllConfigs (0 = not found)
FindConfigIndex(configName) {
    for i, cfg in AllConfigs {
        if (cfg["name"] = configName)
            return i
    }
    return 0
}

; Sync current GUI editing state back into AllConfigs
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

; Refresh config dropdown (GUI only, does not affect hotkeys)
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
        ProcessText.Value := L("Config.Scope.None")
        EnabledCB.Value := 0
        EnabledCB.Enabled := false
        global Mappings := []
        RefreshMappingLV()
    }
    UpdateStatusText()
}

; Parse process string into an array
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

IsValidConfigName(configName) {
    return !RegExMatch(configName, '[\\/:*?"<>|=\[\]]')
}

; Format process scope for display (using parsed arrays)
FormatProcessDisplay(processMode, processList, excludeProcessList) {
    if (processMode = "include") {
        if (processList.Length = 0)
            return L("Config.Scope.Global")
        if (processList.Length = 1)
            return L("Config.Scope.Include.Single", processList[1])
        return L("Config.Scope.Include.Multi", processList[1], processList.Length - 1)
    } else if (processMode = "exclude") {
        if (excludeProcessList.Length = 0)
            return L("Config.Scope.Global")
        if (excludeProcessList.Length = 1)
            return L("Config.Scope.Exclude.Single", excludeProcessList[1])
        return L("Config.Scope.Exclude.Multi", excludeProcessList[1], excludeProcessList.Length - 1)
    }
    return L("Config.Scope.Global")
}

; Update status bar text
UpdateStatusText() {
    enabledCount := 0
    totalCount := AllConfigs.Length
    for _, cfg in AllConfigs {
        if (cfg["enabled"])
            enabledCount++
    }

    statusStr := L("Config.Status.EnabledSummary", enabledCount, totalCount)
    hasWarning := false
    if (HotkeyConflicts.Length > 0) {
        statusStr .= L("Config.Status.ConflictSuffix", HotkeyConflicts.Length)
        hasWarning := true
    }
    if (HotkeyRegErrors.Length > 0) {
        statusStr .= L("Config.Status.RegErrorSuffix", HotkeyRegErrors.Length)
        hasWarning := true
    }

    ; When warnings exist: make status text orange and show detail link
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

; Load specified config into GUI (does not affect hotkey registration)
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

    ; Persist last viewed config name into _state.ini
    try IniWrite(configName, STATE_FILE, "State", "LastConfig")
}

; Save current config to file (atomic write: temp file then replace)
SaveConfig() {
    if (CurrentConfigName = "" || CurrentConfigFile = "")
        return

    tempFile := CurrentConfigFile ".tmp"

    ; Step 1: write all content into a temp file (section by section)
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
        ; If writing temp file fails, original file stays intact; clean up tmp
        try FileDelete(tempFile)
        MsgBox(Format(L("Config.SaveError.WriteTemp"), e.Message, CurrentConfigFile), APP_NAME, "IconX")
        return
    }

    ; Step 2: replace original file with temp file (FileMove overwrite mode)
    try {
        FileMove(tempFile, CurrentConfigFile, 1)
    } catch as e {
        try FileDelete(tempFile)
        MsgBox(Format(L("Config.SaveError.Replace"), e.Message, CurrentConfigFile), APP_NAME, "IconX")
        return
    }

    ; Sync back into AllConfigs and save enabled states
    SyncCurrentToAllConfigs()
    SaveEnabledStates()
}

; Save enabled state for all configs to _state.ini (atomic write)
SaveEnabledStates() {
    tempFile := STATE_FILE ".tmp"
    try {
        ; Ensure config directory exists (defensive: in case it was removed)
        if !DirExist(CONFIG_DIR)
            DirCreate(CONFIG_DIR)

        if FileExist(tempFile)
            FileDelete(tempFile)

        ; Preserve [State] section and always write LastConfig / UILanguage
        lastConfig := ""
        if FileExist(STATE_FILE)
            lastConfig := IniRead(STATE_FILE, "State", "LastConfig", "")
        IniWrite(lastConfig, tempFile, "State", "LastConfig")

        ; Persist UI language
        global CurrentLangCode
        IniWrite(CurrentLangCode, tempFile, "State", "UILanguage")

        for _, cfg in AllConfigs
            IniWrite(cfg["enabled"] ? "1" : "0", tempFile, "EnabledConfigs", cfg["name"])

        FileMove(tempFile, STATE_FILE, 1)
    } catch as e {
        try FileDelete(tempFile)
        MsgBox(Format(L("Config.SaveEnabledStatesError"), e.Message), APP_NAME, "IconX")
    }
}

; Refresh mapping ListView display
RefreshMappingLV() {
    MappingLV.Delete()
    for idx, mapping in Mappings {
        holdText := mapping["HoldRepeat"] ? L("Config.Mapping.HoldYes") : L("Config.Mapping.HoldNo")
        modDisplay := mapping["ModifierKey"] != "" ? KeyToDisplay(mapping["ModifierKey"]) : ""
        ptText := ""
        if (mapping["ModifierKey"] != "")
            ptText := mapping["PassthroughMod"] ? L("Config.Mapping.ModMode.Pass") : L("Config.Mapping.ModMode.Block")
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
    ; Auto-adjust column widths
    loop 8
        MappingLV.ModifyCol(A_Index, "AutoHdr")
}

