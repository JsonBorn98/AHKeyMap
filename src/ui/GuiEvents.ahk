; ============================================================================
; AHKeyMap - GUI event handling module
; Handles all GUI events for config and mapping management
; ============================================================================

; Declare globals shared across modules
global APP_NAME
global CONFIG_DIR
global STATE_FILE
global ConfigDDL
global MappingLV
global EditingIndex

; ============================================================================
; GUI event handlers - config management
; ============================================================================

OnConfigSelect(ctrl, *) {
    selected := ctrl.Text
    if (selected = "")
        return
    if (selected = ConfigStore.Instance.SelectedName)
        return
    ConfigStore.Instance.Select(selected)
}

; Enable/disable the current config via checkbox
OnToggleEnabled(ctrl, *) {
    if (ConfigStore.Instance.SelectedName = "")
        return
    ConfigStore.Instance.SetEnabled(ctrl.Value ? true : false)
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

    if FileExist(CONFIG_DIR "\" configName ".ini") {
        MsgBox(Format(L("GuiEvents.Error.ConfigExists"), configName), APP_NAME, "Icon!")
        return
    }

    processMode := GetSelectedScopeMode(newGui)
    procStr := ProcTextToStr(newGui["ProcName"].Value)

    DestroyModalGui(newGui)
    ConfigStore.Instance.CreateConfig(configName, processMode, procStr)
}

; Copy config
OnCopyConfig(*) {
    if (ConfigStore.Instance.SelectedName = "") {
        MsgBox(L("GuiEvents.Error.NoConfigSelected"), APP_NAME, "Icon!")
        return
    }

    copyGui := CreateModalGui(L("GuiEvents.CopyConfig.Title"))
    copyGui.SetFont("s9", "Microsoft YaHei UI")

    copyGui.AddText("x10 y10 w80 h23 +0x200", L("GuiEvents.CopyConfig.NewNameLabel"))
    defaultName := ConfigStore.Instance.SelectedName "_copy"
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

    if FileExist(CONFIG_DIR "\" newName ".ini") {
        MsgBox(Format(L("GuiEvents.Error.ConfigExists"), newName), APP_NAME, "Icon!")
        return
    }

    DestroyModalGui(copyGui)
    ConfigStore.Instance.CopyConfig(newName)
}

OnDeleteConfig(*) {
    if (ConfigStore.Instance.SelectedName = "") {
        MsgBox(L("GuiEvents.Error.NoConfigSelected"), APP_NAME, "Icon!")
        return
    }

    result := MsgBox(Format(L("GuiEvents.Confirm.DeleteConfig"), ConfigStore.Instance.SelectedName), APP_NAME, "YesNo Icon?")
    if (result = "Yes")
        ConfigStore.Instance.DeleteConfig()
}

OnChangeProcess(*) {
    if (ConfigStore.Instance.SelectedName = "") {
        MsgBox(L("GuiEvents.Error.NoConfigSelected"), APP_NAME, "Icon!")
        return
    }

    cfg := ConfigStore.Instance.Selected()
    if (cfg = "")
        return

    changeGui := CreateModalGui(L("GuiEvents.ChangeScope.Title"))
    changeGui.SetFont("s9", "Microsoft YaHei UI")

    ; Three-state radio group
    changeGui.AddGroupBox("x10 y5 w370 h210", L("GuiEvents.ChangeScope.ModeGroup"))
    globalRadio := changeGui.AddRadio("x20 y25 w350 h20 vScopeGlobalRadio", L("GuiEvents.NewConfig.ScopeGlobal"))
    includeRadio := changeGui.AddRadio("x20 y48 w350 h20 vScopeIncludeRadio", L("GuiEvents.NewConfig.ScopeInclude"))
    excludeRadio := changeGui.AddRadio("x20 y71 w350 h20 vScopeExcludeRadio", L("GuiEvents.NewConfig.ScopeExclude"))

    ; Select radio based on current mode
    if (cfg["processMode"] = "include")
        includeRadio.Value := 1
    else if (cfg["processMode"] = "exclude")
        excludeRadio.Value := 1
    else
        globalRadio.Value := 1

    changeGui.AddText("x20 y98 w60 h23 +0x200", L("GuiEvents.NewConfig.ProcessListLabel"))
    changeGui.AddText("x20 y120 w350 h16 cGray", L("GuiEvents.NewConfig.ProcessListHint"))

    ; Populate process list text based on current mode
    displayProc := ""
    if (cfg["processMode"] = "include")
        displayProc := StrReplace(cfg["process"], "|", "`n")
    else if (cfg["processMode"] = "exclude")
        displayProc := StrReplace(cfg["excludeProcess"], "|", "`n")

    procEdit := changeGui.AddEdit("x20 y138 w290 h65 vProcName Multi", displayProc)
    procPickBtn2 := changeGui.AddButton("x315 y138 w55 h25 vProcessPickButton", L("GuiEvents.Common.ProcessPickButton"))
    procPickBtn2.OnEvent("Click", (*) => ShowProcessPicker(procEdit, true))

    ; Disable process editing when in global mode
    isGlobal := (cfg["processMode"] = "global")
    SetScopeEditorEnabled(procEdit, procPickBtn2, !isGlobal)

    globalRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn2, false))
    includeRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn2, true))
    excludeRadio.OnEvent("Click", (*) => SetScopeEditorEnabled(procEdit, procPickBtn2, true))

    changeGui.AddButton("x100 y222 w80 h28", L("GuiEvents.Common.OkButton")).OnEvent("Click", OnChangeProcessOK.Bind(changeGui))
    changeGui.AddButton("x200 y222 w80 h28", L("GuiEvents.Common.CancelButton")).OnEvent("Click", (*) => DestroyModalGui(changeGui))

    changeGui.Show("w390 h260")
}

OnChangeProcessOK(changeGui, *) {
    processMode := GetSelectedScopeMode(changeGui)
    procStr := ProcTextToStr(changeGui["ProcName"].Value)

    ConfigStore.Instance.SetScope(processMode, procStr)
    DestroyModalGui(changeGui)
}

; ============================================================================
; GUI event handlers - mapping management
; ============================================================================

OnAddMapping(*) {
    if (ConfigStore.Instance.SelectedName = "") {
        MsgBox(L("GuiEvents.Error.SelectOrCreateConfig"), APP_NAME, "Icon!")
        return
    }
    global EditingIndex := 0
    ShowEditMappingGui()
}

OnEditMapping(ctrl, rowNum := 0, *) {
    if (ConfigStore.Instance.SelectedName = "") {
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
    if (ConfigStore.Instance.SelectedName = "") {
        MsgBox(L("GuiEvents.Error.SelectOrCreateConfig"), APP_NAME, "Icon!")
        return
    }

    rowNum := MappingLV.GetNext(0, "F")
    if (rowNum = 0) {
        MsgBox(L("GuiEvents.Error.SelectMappingFirst"), APP_NAME, "Icon!")
        return
    }

    srcMapping := ConfigStore.Instance.SelectedMappings()[rowNum]
    newMapping := Map()
    for key, val in srcMapping
        newMapping[key] := val

    newIdx := ConfigStore.Instance.AddMapping(newMapping)

    MappingLV.Modify(newIdx, "Select Focus Vis")
    global EditingIndex := newIdx
    ShowEditMappingGui()
}

OnDeleteMapping(*) {
    if (ConfigStore.Instance.SelectedName = "") {
        MsgBox(L("GuiEvents.Error.SelectOrCreateConfig"), APP_NAME, "Icon!")
        return
    }

    rowNum := MappingLV.GetNext(0, "F")
    if (rowNum = 0) {
        MsgBox(L("GuiEvents.Error.SelectMappingFirst"), APP_NAME, "Icon!")
        return
    }

    result := MsgBox(L("GuiEvents.Confirm.DeleteMapping"), APP_NAME, "YesNo Icon?")
    if (result = "Yes")
        ConfigStore.Instance.DeleteMapping(rowNum)
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
