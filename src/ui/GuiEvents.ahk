; ============================================================================
; AHKeyMap - GUI event handling module
; Handles all GUI events for config and mapping management
; ============================================================================

; Declare globals shared across modules
global APP_NAME
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
global MappingLV
global EditingIndex

; ============================================================================
; GUI event handlers - config management
; ============================================================================

OnConfigSelect(ctrl, *) {
    selected := ctrl.Text
    if (selected != "" && selected != CurrentConfigName) {
        LoadConfigToGui(selected)
    } else if (selected != "" && CurrentConfigName = "") {
        LoadConfigToGui(selected)
    }
}

; Enable/disable the current config via checkbox
OnToggleEnabled(ctrl, *) {
    if (CurrentConfigName = "")
        return
    global CurrentConfigEnabled := ctrl.Value ? true : false
    SyncCurrentToAllConfigs()
    SaveEnabledStates()
    ReloadConfigHotkeys(CurrentConfigName)
    UpdateStatusText()
}

OnNewConfig(*) {
    newGui := CreateModalGui(L("GuiEvents.NewConfig.Title"))
    newGui.SetFont("s9", "Microsoft YaHei UI")

    newGui.AddText("x10 y10 w80 h23 +0x200", L("GuiEvents.NewConfig.NameLabel"))
    nameEdit := newGui.AddEdit("x90 y10 w250 h23 vConfigName")

    ; Three-state process mode radios
    newGui.AddGroupBox("x10 y42 w330 h175", L("GuiEvents.NewConfig.ScopeGroup"))
    globalRadio := newGui.AddRadio("x20 y62 w310 h20 vScopeGlobalRadio Checked", L("GuiEvents.NewConfig.ScopeGlobal"))
    includeRadio := newGui.AddRadio("x20 y85 w310 h20 vScopeIncludeRadio", L("GuiEvents.NewConfig.ScopeInclude"))
    excludeRadio := newGui.AddRadio("x20 y108 w310 h20 vScopeExcludeRadio", L("GuiEvents.NewConfig.ScopeExclude"))

    newGui.AddText("x20 y133 w60 h23 +0x200", L("GuiEvents.NewConfig.ProcessListLabel"))
    procEdit := newGui.AddEdit("x85 y133 w195 h70 vProcName Multi")
    procEdit.Enabled := false
    procPickBtn := newGui.AddButton("x285 y133 w45 h25 vProcessPickButton", L("GuiEvents.Common.ProcessPickButton"))
    procPickBtn.OnEvent("Click", (*) => ShowProcessPicker(procEdit, true))
    procPickBtn.Enabled := false

    ; Enable/disable process editors when radio buttons change
    globalRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn, false))
    includeRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn, true))
    excludeRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn, true))

    newGui.AddButton("x100 y225 w80 h28", L("GuiEvents.Common.OkButton")).OnEvent("Click", OnNewConfigOK.Bind(newGui))
    newGui.AddButton("x190 y225 w80 h28", L("GuiEvents.Common.CancelButton")).OnEvent("Click", (*) => DestroyModalGui(newGui))

    newGui.Show("w350 h265")
}

OnNewConfigOK(newGui, *) {
    configName := Trim(newGui["ConfigName"].Value)

    if (configName = "") {
        MsgBox(L("GuiEvents.Error.NameRequired"), APP_NAME, "Icon!")
        return
    }

    if !IsValidConfigName(configName) {
        MsgBox(L("GuiEvents.Error.NameInvalidChars"), APP_NAME, "Icon!")
        return
    }

    configFile := CONFIG_DIR "\" configName ".ini"
    if FileExist(configFile) {
        MsgBox(Format(L("GuiEvents.Error.ConfigExists"), configName), APP_NAME, "Icon!")
        return
    }

    ; Determine process mode and process list
    processMode := GetSelectedScopeMode(newGui)
    procStr := ProcTextToStr(newGui["ProcName"].Value)

    IniWrite(configName, configFile, "Meta", "Name")
    IniWrite(processMode, configFile, "Meta", "ProcessMode")
    if (processMode = "include") {
        IniWrite(procStr, configFile, "Meta", "Process")
        IniWrite("", configFile, "Meta", "ExcludeProcess")
    } else if (processMode = "exclude") {
        IniWrite("", configFile, "Meta", "Process")
        IniWrite(procStr, configFile, "Meta", "ExcludeProcess")
    } else {
        IniWrite("", configFile, "Meta", "Process")
        IniWrite("", configFile, "Meta", "ExcludeProcess")
    }

    ; Enable new config by default
    IniWrite("1", STATE_FILE, "EnabledConfigs", configName)

    DestroyModalGui(newGui)

    ; Reload all configs
    LoadAllConfigs()
    RefreshConfigList(configName)
    ReloadAllHotkeys()
}

; Copy config
OnCopyConfig(*) {
    if (CurrentConfigName = "") {
        MsgBox(L("GuiEvents.Error.NoConfigSelected"), APP_NAME, "Icon!")
        return
    }

    copyGui := CreateModalGui(L("GuiEvents.CopyConfig.Title"))
    copyGui.SetFont("s9", "Microsoft YaHei UI")

    copyGui.AddText("x10 y10 w80 h23 +0x200", L("GuiEvents.CopyConfig.NewNameLabel"))
    defaultName := CurrentConfigName "_copy"
    nameEdit := copyGui.AddEdit("x90 y10 w250 h23 vNewName", defaultName)

    copyGui.AddButton("x110 y48 w80 h28", L("GuiEvents.Common.OkButton")).OnEvent("Click", OnCopyConfigOK.Bind(copyGui))
    copyGui.AddButton("x200 y48 w80 h28", L("GuiEvents.Common.CancelButton")).OnEvent("Click", (*) => DestroyModalGui(copyGui))

    copyGui.Show("w350 h88")
}

OnCopyConfigOK(copyGui, *) {
    newName := Trim(copyGui["NewName"].Value)

    if (newName = "") {
        MsgBox(L("GuiEvents.Error.NameRequired"), APP_NAME, "Icon!")
        return
    }

    if !IsValidConfigName(newName) {
        MsgBox(L("GuiEvents.Error.NameInvalidChars"), APP_NAME, "Icon!")
        return
    }

    newFile := CONFIG_DIR "\" newName ".ini"
    if FileExist(newFile) {
        MsgBox(Format(L("GuiEvents.Error.ConfigExists"), newName), APP_NAME, "Icon!")
        return
    }

    ; Copy current config file
    if FileExist(CurrentConfigFile)
        FileCopy(CurrentConfigFile, newFile)

    ; Update Name field inside copied config
    IniWrite(newName, newFile, "Meta", "Name")

    ; Enable new config by default
    IniWrite("1", STATE_FILE, "EnabledConfigs", newName)

    DestroyModalGui(copyGui)

    ; Reload all configs
    LoadAllConfigs()
    RefreshConfigList(newName)
    ReloadAllHotkeys()
}

OnDeleteConfig(*) {
    if (CurrentConfigName = "") {
        MsgBox(L("GuiEvents.Error.NoConfigSelected"), APP_NAME, "Icon!")
        return
    }

    result := MsgBox(Format(L("GuiEvents.Confirm.DeleteConfig"), CurrentConfigName), APP_NAME, "YesNo Icon?")
    if (result = "Yes")
        DeleteCurrentConfigAndRefresh()
}

OnChangeProcess(*) {
    if (CurrentConfigName = "") {
        MsgBox(L("GuiEvents.Error.NoConfigSelected"), APP_NAME, "Icon!")
        return
    }

    changeGui := CreateModalGui(L("GuiEvents.ChangeScope.Title"))
    changeGui.SetFont("s9", "Microsoft YaHei UI")

    ; Three-state radio group
    changeGui.AddGroupBox("x10 y5 w370 h210", L("GuiEvents.ChangeScope.ModeGroup"))
    globalRadio := changeGui.AddRadio("x20 y25 w350 h20 vScopeGlobalRadio", L("GuiEvents.NewConfig.ScopeGlobal"))
    includeRadio := changeGui.AddRadio("x20 y48 w350 h20 vScopeIncludeRadio", L("GuiEvents.NewConfig.ScopeInclude"))
    excludeRadio := changeGui.AddRadio("x20 y71 w350 h20 vScopeExcludeRadio", L("GuiEvents.NewConfig.ScopeExclude"))

    ; Select radio based on current mode
    if (CurrentProcessMode = "include")
        includeRadio.Value := 1
    else if (CurrentProcessMode = "exclude")
        excludeRadio.Value := 1
    else
        globalRadio.Value := 1

    changeGui.AddText("x20 y98 w60 h23 +0x200", L("GuiEvents.NewConfig.ProcessListLabel"))
    changeGui.AddText("x20 y120 w350 h16 cGray", L("GuiEvents.NewConfig.ProcessListHint"))

    ; Populate process list text based on current mode
    displayProc := ""
    if (CurrentProcessMode = "include")
        displayProc := StrReplace(CurrentProcess, "|", "`n")
    else if (CurrentProcessMode = "exclude")
        displayProc := StrReplace(CurrentExcludeProcess, "|", "`n")

    procEdit := changeGui.AddEdit("x20 y138 w290 h65 vProcName Multi", displayProc)
    procPickBtn2 := changeGui.AddButton("x315 y138 w55 h25 vProcessPickButton", L("GuiEvents.Common.ProcessPickButton"))
    procPickBtn2.OnEvent("Click", (*) => ShowProcessPicker(procEdit, true))

    ; Disable process editing when in global mode
    isGlobal := (CurrentProcessMode = "global")
    SetScopeEditorEnabled(procEdit, procPickBtn2, !isGlobal)

    globalRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn2, false))
    includeRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn2, true))
    excludeRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn2, true))

    changeGui.AddButton("x100 y222 w80 h28", L("GuiEvents.Common.OkButton")).OnEvent("Click", OnChangeProcessOK.Bind(changeGui))
    changeGui.AddButton("x200 y222 w80 h28", L("GuiEvents.Common.CancelButton")).OnEvent("Click", (*) => DestroyModalGui(changeGui))

    changeGui.Show("w390 h260")
}

OnChangeProcessOK(changeGui, *) {
    ; Determine process mode and process list
    processMode := GetSelectedScopeMode(changeGui)
    procStr := ProcTextToStr(changeGui["ProcName"].Value)

    global CurrentProcessMode := processMode
    if (processMode = "include") {
        global CurrentProcess := procStr
        global CurrentProcessList := ParseProcessList(procStr)
        global CurrentExcludeProcess := ""
        global CurrentExcludeProcessList := []
    } else if (processMode = "exclude") {
        global CurrentProcess := ""
        global CurrentProcessList := []
        global CurrentExcludeProcess := procStr
        global CurrentExcludeProcessList := ParseProcessList(procStr)
    } else {
        global CurrentProcess := ""
        global CurrentProcessList := []
        global CurrentExcludeProcess := ""
        global CurrentExcludeProcessList := []
    }

    ProcessText.Value := FormatProcessDisplay(CurrentProcessMode, CurrentProcessList, CurrentExcludeProcessList)

    SaveConfig()
    ReloadConfigHotkeys(CurrentConfigName)
    DestroyModalGui(changeGui)
}

; ============================================================================
; GUI event handlers - mapping management
; ============================================================================

OnAddMapping(*) {
    if (CurrentConfigName = "") {
        MsgBox(L("GuiEvents.Error.SelectOrCreateConfig"), APP_NAME, "Icon!")
        return
    }
    global EditingIndex := 0
    ShowEditMappingGui()
}

OnEditMapping(ctrl, rowNum := 0, *) {
    if (CurrentConfigName = "") {
        MsgBox(L("GuiEvents.Error.SelectOrCreateConfig"), APP_NAME, "Icon!")
        return
    }

    if (ctrl = MappingLV) {
        if (rowNum = 0)
            return
        global EditingIndex := rowNum
    } else {
        rowNum := MappingLV.GetNext(0, "F")
        if (rowNum = 0) {
            MsgBox(L("GuiEvents.Error.SelectMappingFirst"), APP_NAME, "Icon!")
            return
        }
        global EditingIndex := rowNum
    }
    ShowEditMappingGui()
}

OnCopyMapping(*) {
    if (CurrentConfigName = "") {
        MsgBox(L("GuiEvents.Error.SelectOrCreateConfig"), APP_NAME, "Icon!")
        return
    }

    rowNum := MappingLV.GetNext(0, "F")
    if (rowNum = 0) {
        MsgBox(L("GuiEvents.Error.SelectMappingFirst"), APP_NAME, "Icon!")
        return
    }

    srcMapping := Mappings[rowNum]
    newMapping := Map()
    for key, val in srcMapping
        newMapping[key] := val
    Mappings.Push(newMapping)

    SaveConfig()
    RefreshMappingLV()
    ReloadConfigHotkeys(CurrentConfigName)

    newIdx := Mappings.Length
    MappingLV.Modify(newIdx, "Select Focus Vis")
    global EditingIndex := newIdx
    ShowEditMappingGui()
}

OnDeleteMapping(*) {
    if (CurrentConfigName = "") {
        MsgBox(L("GuiEvents.Error.SelectOrCreateConfig"), APP_NAME, "Icon!")
        return
    }

    rowNum := MappingLV.GetNext(0, "F")
    if (rowNum = 0) {
        MsgBox(L("GuiEvents.Error.SelectMappingFirst"), APP_NAME, "Icon!")
        return
    }

    result := MsgBox(L("GuiEvents.Confirm.DeleteMapping"), APP_NAME, "YesNo Icon?")
    if (result = "Yes") {
        Mappings.RemoveAt(rowNum)
        SaveConfig()
        RefreshMappingLV()
        ReloadConfigHotkeys(CurrentConfigName)
    }
}

; ============================================================================
; Private helper functions
; ============================================================================

GetSelectedScopeMode(scopeGui) {
    if scopeGui["ScopeIncludeRadio"].Value
        return "include"
    if scopeGui["ScopeExcludeRadio"].Value
        return "exclude"
    return "global"
}

; Convert multi-line process text (one per line) into a | separated string
ProcTextToStr(rawText) {
    procStr := ""
    loop parse rawText, "`n", "`r" {
        trimmed := Trim(A_LoopField)
        if (trimmed != "") {
            if (procStr != "")
                procStr .= "|"
            procStr .= trimmed
        }
    }
    return procStr
}

SetScopeEditorEnabled(procEdit, procPickBtn, isEnabled) {
    procEdit.Enabled := isEnabled
    procPickBtn.Enabled := isEnabled
}

DeleteCurrentConfigAndRefresh() {
    if FileExist(CurrentConfigFile)
        FileDelete(CurrentConfigFile)

    idx := FindConfigIndex(CurrentConfigName)
    if (idx > 0)
        AllConfigs.RemoveAt(idx)

    SaveEnabledStates()
    global CurrentConfigName := ""
    global CurrentConfigFile := ""
    global Mappings := []

    ReloadAllHotkeys()
    RefreshConfigList()
}


