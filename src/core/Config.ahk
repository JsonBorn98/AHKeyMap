; ============================================================================
; AHKeyMap - Config management module
; Pure config/state INI I/O plus the main-window render functions
; ============================================================================

; Globals shared across modules
global APP_NAME
global SCRIPT_DIR
global CONFIG_DIR
global STATE_FILE
global AllConfigs
global ConfigDDL
global EnabledCB
global ProcessText
global StatusText
global StatusDetailLink
global StatusHasWarning
global MappingLV
global HotkeyConflicts
global HotkeyRegErrors

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

    ; Read enabled state from _state.ini
    enabledVal := "1"
    if FileExist(STATE_FILE)
        enabledVal := IniRead(STATE_FILE, "EnabledConfigs", configName, "1")
    enabled := (enabledVal = "1")

    ; Read mappings (Mapping.Make enforces the record invariants, including
    ; clamping hand-edited sub-minimum repeat timing at load time)
    mappings := []
    idx := 1
    loop {
        section := "Mapping" idx
        sourceKey := IniRead(configFile, section, "SourceKey", "")
        if (sourceKey = "")
            break

        mappings.Push(Mapping.Make(
            IniRead(configFile, section, "ModifierKey", ""),
            sourceKey,
            IniRead(configFile, section, "TargetKey", ""),
            IniRead(configFile, section, "HoldRepeat", "0"),
            IniRead(configFile, section, "RepeatDelay", ""),
            IniRead(configFile, section, "RepeatInterval", ""),
            IniRead(configFile, section, "PassthroughMod", "0")))
        idx++
    }

    return ConfigRecord.Make(configName, processMode, process, excludeProcess, enabled, mappings)
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

; Serialize one config record to its INI file (atomic write: temp file then replace)
SaveConfig(cfg) {
    configFile := cfg["file"]
    tempFile := configFile ".tmp"

    ; Step 1: write all content into a temp file (section by section)
    try {
        if FileExist(tempFile)
            FileDelete(tempFile)

        metaPairs := "Name=" cfg["name"]
        metaPairs .= "`nProcessMode=" cfg["processMode"]
        metaPairs .= "`nProcess=" cfg["process"]
        metaPairs .= "`nExcludeProcess=" cfg["excludeProcess"]
        IniWrite(metaPairs, tempFile, "Meta")

        for idx, m in cfg["mappings"] {
            pairs := ""
            for iniKey, iniVal in Mapping.ToIniPairs(m) {
                if (pairs != "")
                    pairs .= "`n"
                pairs .= iniKey "=" iniVal
            }
            IniWrite(pairs, tempFile, "Mapping" idx)
        }
    } catch as e {
        ; If writing temp file fails, original file stays intact; clean up tmp
        try FileDelete(tempFile)
        MsgBox(Format(L("Config.SaveError.WriteTemp"), e.Message, configFile), APP_NAME, "IconX")
        return
    }

    ; Step 2: replace original file with temp file (FileMove overwrite mode)
    try {
        FileMove(tempFile, configFile, 1)
    } catch as e {
        try FileDelete(tempFile)
        MsgBox(Format(L("Config.SaveError.Replace"), e.Message, configFile), APP_NAME, "IconX")
    }
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

; ============================================================================
; Main-window render functions
; ============================================================================

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

    if !IsObject(ConfigDDL) {
        ; No GUI (headless tests): just track the selection in the store
        if (selectIdx > 0)
            ConfigStore.Instance.Select(configs[selectIdx])
        else
            ConfigStore.Instance.Select("")
        return
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
        ConfigStore.Instance.Select("")
    }
    UpdateStatusText()
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
    if (StatusText = "" || StatusDetailLink = "")
        return

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

; Refresh mapping ListView display (no-op without a GUI)
RefreshMappingLV() {
    if !IsObject(MappingLV)
        return
    MappingLV.Delete()
    for idx, mapping in ConfigStore.Instance.SelectedMappings() {
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
