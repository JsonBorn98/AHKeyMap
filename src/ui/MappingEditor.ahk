; ============================================================================
; AHKeyMap - Mapping editor dialog module
; Builds the mapping editor window and handles its events
; ============================================================================

; Declare globals shared across modules
global APP_NAME
global MainGui
global DEFAULT_REPEAT_DELAY
global DEFAULT_REPEAT_INTERVAL

; GUI control references (editor-owned protocol: .Value holds the display
; text, .ahkKey holds the AHK key syntax)
global EditModifierEdit
global EditSourceEdit
global EditTargetEdit
global EditHoldRepeatCB
global EditDelayEdit
global EditIntervalEdit
global EditPassthroughCB
global EditingIndex

; ============================================================================
; Mapping editor dialog
; ============================================================================

ShowEditMappingGui() {
    global EditGui := CreateModalGui(EditingIndex > 0 ? L("MappingEditor.Title.Edit") : L("MappingEditor.Title.New"))
    EditGui.SetFont("s9", "Microsoft YaHei UI")

    ; Modifier row
    EditGui.AddText("x10 y10 w70 h23 +0x200", L("MappingEditor.ModifierLabel"))
    global EditModifierEdit := EditGui.AddEdit("x80 y10 w180 h23 vModifierKey ReadOnly")
    EditGui.AddButton("x265 y9 w65 h25", L("MappingEditor.CaptureButton")).OnEvent("Click", OnCaptureModifier)
    EditGui.AddButton("x335 y9 w50 h25", L("MappingEditor.ClearButton")).OnEvent("Click", OnClearModifier)

    ; Source key
    EditGui.AddText("x10 y45 w70 h23 +0x200", L("MappingEditor.SourceLabel"))
    global EditSourceEdit := EditGui.AddEdit("x80 y45 w180 h23 vSourceKey ReadOnly")
    EditGui.AddButton("x265 y44 w65 h25", L("MappingEditor.CaptureButton")).OnEvent("Click", OnCaptureSource)

    ; Target key
    EditGui.AddText("x10 y80 w70 h23 +0x200", L("MappingEditor.TargetLabel"))
    global EditTargetEdit := EditGui.AddEdit("x80 y80 w180 h23 vTargetKey ReadOnly")
    EditGui.AddButton("x265 y79 w65 h25", L("MappingEditor.CaptureButton")).OnEvent("Click", OnCaptureTarget)

    ; Long-press repeat
    global EditHoldRepeatCB := EditGui.AddCheckbox("x10 y115 w150 h23 vHoldRepeat", L("MappingEditor.HoldRepeatLabel"))
    EditHoldRepeatCB.OnEvent("Click", OnHoldRepeatToggle)

    ; Repeat delay
    EditGui.AddText("x10 y145 w100 h23 +0x200", L("MappingEditor.DelayLabel"))
    global EditDelayEdit := EditGui.AddEdit("x110 y145 w80 h23 vRepeatDelay Number")
    EditDelayEdit.Value := String(DEFAULT_REPEAT_DELAY)

    ; Repeat interval
    EditGui.AddText("x200 y145 w100 h23 +0x200", L("MappingEditor.IntervalLabel"))
    global EditIntervalEdit := EditGui.AddEdit("x300 y145 w80 h23 vRepeatInterval Number")
    EditIntervalEdit.Value := String(DEFAULT_REPEAT_INTERVAL)

    ; Keep original modifier behavior
    global EditPassthroughCB := EditGui.AddCheckbox("x10 y175 w370 h23 vPassthroughMod", L("MappingEditor.PassthroughLabel"))

    ; In edit mode, populate fields from existing mapping
    mappings := ConfigStore.Instance.SelectedMappings()
    if (EditingIndex > 0 && EditingIndex <= mappings.Length) {
        m := mappings[EditingIndex]
        EditModifierEdit.Value := KeyToDisplay(m["ModifierKey"])
        EditModifierEdit.ahkKey := m["ModifierKey"]
        EditSourceEdit.Value := KeyToDisplay(m["SourceKey"])
        EditSourceEdit.ahkKey := m["SourceKey"]
        EditTargetEdit.Value := KeyToDisplay(m["TargetKey"])
        EditTargetEdit.ahkKey := m["TargetKey"]
        EditHoldRepeatCB.Value := m["HoldRepeat"]
        EditDelayEdit.Value := m["RepeatDelay"]
        EditIntervalEdit.Value := m["RepeatInterval"]
        EditPassthroughCB.Value := m["PassthroughMod"]
    } else {
        EditModifierEdit.ahkKey := ""
        EditSourceEdit.ahkKey := ""
        EditTargetEdit.ahkKey := ""
    }

    ; Enable/disable controls based on current state
    OnHoldRepeatToggle(EditHoldRepeatCB, "")
    UpdatePassthroughState()

    ; Buttons
    EditGui.AddButton("x100 y210 w80 h28", L("MappingEditor.OkButton")).OnEvent("Click", OnEditMappingOK)
    EditGui.AddButton("x190 y210 w80 h28", L("MappingEditor.CancelButton")).OnEvent("Click", (*) => DestroyModalGui(EditGui))
    EditGui.Show("w395 h250")
}

OnClearModifier(*) {
    EditModifierEdit.Value := ""
    EditModifierEdit.ahkKey := ""
    UpdatePassthroughState()
}

; ---- Key capture entries: bind a capture target to its completion callback ----

OnCaptureModifier(*) {
    StartCapture("modifier", OnModifierCaptured)
}

OnCaptureSource(*) {
    StartCapture("source", OnSourceCaptured)
}

OnCaptureTarget(*) {
    StartCapture("target", OnTargetCaptured)
}

; ---- Capture completion callbacks: write the editor's own controls ----

OnModifierCaptured(ahkKey, displayKey) {
    EditModifierEdit.Value := displayKey
    EditModifierEdit.ahkKey := ahkKey
    UpdatePassthroughState()
}

OnSourceCaptured(ahkKey, displayKey) {
    EditSourceEdit.Value := displayKey
    EditSourceEdit.ahkKey := ahkKey
}

OnTargetCaptured(ahkKey, displayKey) {
    EditTargetEdit.Value := displayKey
    EditTargetEdit.ahkKey := ahkKey
}

; "Keep modifier behavior" option is only meaningful when a modifier is set
UpdatePassthroughState() {
    hasModifier := EditModifierEdit.ahkKey != ""
    EditPassthroughCB.Enabled := hasModifier
    if !hasModifier
        EditPassthroughCB.Value := 0
}

OnHoldRepeatToggle(ctrl, *) {
    isEnabled := ctrl.Value
    EditDelayEdit.Enabled := isEnabled
    EditIntervalEdit.Enabled := isEnabled
}

OnEditMappingOK(*) {
    modifierAhk := EditModifierEdit.ahkKey
    sourceAhk := EditSourceEdit.ahkKey
    targetAhk := EditTargetEdit.ahkKey

    if (sourceAhk = "") {
        MsgBox(L("MappingEditor.Error.SourceRequired"), APP_NAME, "Icon!")
        return
    }
    if (targetAhk = "") {
        MsgBox(L("MappingEditor.Error.TargetRequired"), APP_NAME, "Icon!")
        return
    }

    repeatDelay := EditDelayEdit.Value != "" ? Integer(EditDelayEdit.Value) : DEFAULT_REPEAT_DELAY
    repeatInterval := EditIntervalEdit.Value != "" ? Integer(EditIntervalEdit.Value) : DEFAULT_REPEAT_INTERVAL
    if (repeatDelay < 10)
        repeatDelay := 10
    if (repeatInterval < 10)
        repeatInterval := 10

    mapping := Map()
    mapping["ModifierKey"] := modifierAhk
    mapping["SourceKey"] := sourceAhk
    mapping["TargetKey"] := targetAhk
    mapping["HoldRepeat"] := EditHoldRepeatCB.Value ? 1 : 0
    mapping["RepeatDelay"] := repeatDelay
    mapping["RepeatInterval"] := repeatInterval
    mapping["PassthroughMod"] := EditPassthroughCB.Value ? 1 : 0

    if (EditingIndex > 0 && EditingIndex <= ConfigStore.Instance.SelectedMappings().Length) {
        ConfigStore.Instance.ReplaceMapping(EditingIndex, mapping)
    } else {
        ConfigStore.Instance.AddMapping(mapping)
    }

    DestroyModalGui(EditGui)
}
