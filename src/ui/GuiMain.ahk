; ============================================================================
; AHKeyMap - Main window construction module
; Builds the main window UI and owns rendering from application state
; ============================================================================

; Declare globals shared across modules
global APP_NAME
global APP_VERSION
global MainGui
global ConfigDDL
global EnabledCB
global ProcessText
global MappingLV
global StatusText
global StatusDetailLink
global StatusHasWarning
global StatusDetailHovered
global BtnAddMapping
global BtnEditMapping
global BtnCopyMapping
global BtnDeleteMapping
global BtnRunAsAdmin
global LastReloadResult

; ============================================================================
; GUI construction - main window
; ============================================================================

BuildMainGui() {
    ; Window title: append admin marker when running elevated
    title := Format(L("GuiMain.Title"), APP_NAME, APP_VERSION)
    if A_IsAdmin
        title .= L("GuiMain.Title.AdminSuffix")
    global MainGui := Gui("+Resize +MinSize720x400", title)
    MainGui.SetFont("s9", "Microsoft YaHei UI")
    MainGui.OnEvent("Close", OnMainClose)
    MainGui.OnEvent("Size", OnMainResize)

    ; --- Config management row (first row) ---
    MainGui.AddText("x10 y10 w40 h23 +0x200", L("GuiMain.ConfigLabel"))
    global ConfigDDL := MainGui.AddDropDownList("x50 y10 w180 h200 vConfigDDL")
    ConfigDDL.OnEvent("Change", OnConfigSelect)

    global EnabledCB := MainGui.AddCheckbox("x235 y11 w50 h23", L("GuiMain.EnableCheckbox"))
    EnabledCB.OnEvent("Click", OnToggleEnabled)

    MainGui.AddButton("x290 y9 w50 h25", L("GuiMain.NewConfigButton")).OnEvent("Click", OnNewConfig)
    MainGui.AddButton("x345 y9 w50 h25", L("GuiMain.CopyConfigButton")).OnEvent("Click", OnCopyConfig)
    MainGui.AddButton("x400 y9 w50 h25", L("GuiMain.DeleteConfigButton")).OnEvent("Click", OnDeleteConfig)
    MainGui.AddButton("x455 y9 w70 h25", L("GuiMain.ScopeButton")).OnEvent("Click", OnChangeProcess)

    ; Scope text: right-aligned, width adapts
    global ProcessText := MainGui.AddText("x530 y10 w180 h23 +0x200", L("GuiMain.ScopeNone"))

    ; --- Mapping list ---
    global MappingLV := MainGui.AddListView("x10 y45 w700 h360 +Grid -Multi", [
        L("GuiMain.Mapping.ColIndex"),
        L("GuiMain.Mapping.ColModifier"),
        L("GuiMain.Mapping.ColSource"),
        L("GuiMain.Mapping.ColTarget"),
        L("GuiMain.Mapping.ColHoldRepeat"),
        L("GuiMain.Mapping.ColModMode"),
        L("GuiMain.Mapping.ColDelay"),
        L("GuiMain.Mapping.ColInterval")
    ])
    MappingLV.OnEvent("DoubleClick", OnEditMapping)

    ; --- Action button row (bottom bar, Y adjusted in OnMainResize) ---
    btnY := 415
    statusY := btnY + 5
    global BtnAddMapping := MainGui.AddButton("x10 y" btnY " w80 h30", L("GuiMain.AddMappingButton"))
    BtnAddMapping.OnEvent("Click", OnAddMapping)
    global BtnEditMapping := MainGui.AddButton("x95 y" btnY " w80 h30", L("GuiMain.EditMappingButton"))
    BtnEditMapping.OnEvent("Click", OnEditMapping)
    global BtnCopyMapping := MainGui.AddButton("x180 y" btnY " w80 h30", L("GuiMain.CopyMappingButton"))
    BtnCopyMapping.OnEvent("Click", OnCopyMapping)
    global BtnDeleteMapping := MainGui.AddButton("x265 y" btnY " w80 h30", L("GuiMain.DeleteMappingButton"))
    BtnDeleteMapping.OnEvent("Click", OnDeleteMapping)

    ; --- Status bar (left text + right detail link) ---
    global StatusText := MainGui.AddText("x360 y" statusY " w150 h23 +0x200 cGray", L("GuiMain.Status.EnabledSummary", 0, 0))
    global StatusDetailLink := MainGui.AddText("x515 y" statusY " w75 h23 +0x200 c0078D7", L("GuiMain.Status.DetailLink"))
    StatusDetailLink.SetFont("underline")
    StatusDetailLink.OnEvent("Click", OnStatusTextClick)
    StatusDetailLink.Opt("+Hidden")

    ; Detail link hover feedback: highlight + hand cursor
    OnMessage(0x0200, OnMainMouseMove)
    OnMessage(0x0020, OnMainSetCursor)

    ; --- Elevation button ---
    global BtnRunAsAdmin := MainGui.AddButton("x600 y" btnY " w110 h30", L("GuiMain.RunAsAdminButton"))
    BtnRunAsAdmin.OnEvent("Click", OnRunAsAdmin)
    if A_IsAdmin
        BtnRunAsAdmin.Enabled := false

    ; Tray menu
    tray := A_TrayMenu
    tray.Delete()
    showMainLabel := L("Tray.ShowMainWindow")
    autoStartLabel := L("Tray.AutoStart")
    adminTrayItem := L("Tray.RunAsAdmin")
    exitLabel := L("Tray.Exit")

    tray.Add(showMainLabel, OnTrayShow)
    tray.Add()
    tray.Add(autoStartLabel, OnTrayAutoStartToggle)
    if IsAutoStartEnabled()
        tray.Check(autoStartLabel)
    tray.Add()

    ; Language submenu
    langMenu := Menu()
    langMenu.Add(L("Tray.Language.En"), (*) => OnTraySetLanguage("en-US"))
    langMenu.Add(L("Tray.Language.ZhHans"), (*) => OnTraySetLanguage("zh-CN"))
    tray.Add(L("Tray.LanguageMenu"), langMenu)
    tray.Add()

    ; Register the render seam: every store change re-renders this window
    ConfigStore.Instance.SetOnChanged(RenderFromState)
}

; ============================================================================
; Render-from-state entry (registered as the store's OnChanged callback)
; ============================================================================

; One render entry: rebuild every main-window widget from application state.
; Called with the ReloadAllHotkeys result ({conflicts, regErrors}) after
; store mutations, or with "" (keep the last result) for render-only events
; such as selection or language changes. Runs only when the window exists.
RenderFromState(reloadResult) {
    if (MainGui = "")
        return

    if IsObject(reloadResult)
        global LastReloadResult := reloadResult

    RefreshConfigList()
    RefreshScopeControls()
    RefreshMappingLV()
    UpdateStatusText()
}

; Refresh config dropdown from the config list on disk (no hotkey reload)
; Keeps the store selection in sync with what the dropdown shows
RefreshConfigList() {
    configs := GetConfigList()
    items := []
    selectIdx := 0
    selectedName := ConfigStore.Instance.SelectedName
    for i, name in configs {
        items.Push(name)
        if (name = selectedName)
            selectIdx := i
    }

    ConfigDDL.Delete()
    if (items.Length > 0) {
        ConfigDDL.Add(items)
        if (selectIdx > 0)
            ConfigDDL.Choose(selectIdx)
        else
            ConfigDDL.Choose(1)
        ; Adopt the dropdown item as the selection (Choose does not fire Change)
        ConfigStore.Instance.Select(configs[ConfigDDL.Value])
    } else {
        ConfigStore.Instance.Select("")
    }
}

; Refresh the scope text and enable checkbox from the selected config
RefreshScopeControls() {
    cfg := ConfigStore.Instance.Selected()
    if (cfg != "") {
        ProcessText.Value := FormatProcessDisplay(cfg["processMode"], cfg["processList"], cfg["excludeProcessList"])
        EnabledCB.Value := cfg["enabled"]
        EnabledCB.Enabled := true
    } else {
        ProcessText.Value := L("Config.Scope.None")
        EnabledCB.Value := 0
        EnabledCB.Enabled := false
    }
}

; Refresh mapping ListView rows from the selected config's mappings
RefreshMappingLV() {
    rows := BuildMappingRows(ConfigStore.Instance.SelectedMappings())
    MappingLV.Delete()
    for _, row in rows
        MappingLV.Add("", row.idx, row.modifier, row.source, row.target, row.hold, row.mode, row.delay, row.interval)
    ; Auto-adjust column widths
    loop 8
        MappingLV.ModifyCol(A_Index, "AutoHdr")
}

; Update the status bar from the store plus the last reload result
UpdateStatusText() {
    vm := BuildStatusSummary(AllConfigs, LastReloadResult)
    global StatusHasWarning := vm.hasWarning

    if (vm.hasWarning) {
        StatusText.SetFont("cE07B00")
        StatusDetailLink.Opt("-Hidden")
    } else {
        StatusText.SetFont("cGray")
        StatusDetailLink.Opt("+Hidden")
        SetStatusDetailHover(false)
    }
    StatusText.Value := vm.text
}

; ============================================================================
; Pure view-model builders (unit-tested without a window)
; ============================================================================

; Status summary text plus the warning flag
; Returns {text: "...", hasWarning: true|false}
BuildStatusSummary(allConfigs, reloadResult) {
    conflicts := []
    regErrors := []
    if IsObject(reloadResult) {
        conflicts := reloadResult.conflicts
        regErrors := reloadResult.regErrors
    }

    enabledCount := 0
    totalCount := allConfigs.Length
    for _, cfg in allConfigs {
        if (cfg["enabled"])
            enabledCount++
    }

    statusStr := L("Config.Status.EnabledSummary", enabledCount, totalCount)
    hasWarning := false
    if (conflicts.Length > 0) {
        statusStr .= L("Config.Status.ConflictSuffix", conflicts.Length)
        hasWarning := true
    }
    if (regErrors.Length > 0) {
        statusStr .= L("Config.Status.RegErrorSuffix", regErrors.Length)
        hasWarning := true
    }

    return { text: statusStr, hasWarning: hasWarning }
}

; Mapping rows for the ListView (one row object per mapping, in order)
; Each row: {idx, modifier, source, target, hold, mode, delay, interval}
BuildMappingRows(mappings) {
    rows := []
    for idx, mapping in mappings {
        holdText := mapping["HoldRepeat"] ? L("Config.Mapping.HoldYes") : L("Config.Mapping.HoldNo")
        modDisplay := mapping["ModifierKey"] != "" ? KeyToDisplay(mapping["ModifierKey"]) : ""
        ptText := ""
        if (mapping["ModifierKey"] != "")
            ptText := mapping["PassthroughMod"] ? L("Config.Mapping.ModMode.Pass") : L("Config.Mapping.ModMode.Block")
        delayText := mapping["HoldRepeat"] ? mapping["RepeatDelay"] : ""
        intervalText := mapping["HoldRepeat"] ? mapping["RepeatInterval"] : ""
        rows.Push({
            idx: idx,
            modifier: modDisplay,
            source: KeyToDisplay(mapping["SourceKey"]),
            target: KeyToDisplay(mapping["TargetKey"]),
            hold: holdText,
            mode: ptText,
            delay: delayText,
            interval: intervalText
        })
    }
    return rows
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

; Main window resize handler
; Three-row layout: fixed top (h45) | resizable ListView | fixed bottom (h45)
OnMainResize(thisGui, minMax, width, height) {
    if (minMax = -1)
        return

    ; Layout constants
    topH := 45      ; top area height (y=0 to ListView start)
    bottomH := 45   ; bottom bar height
    margin := 10    ; horizontal margin

    ; ListView: fill middle area
    lvW := width - margin * 2
    lvH := height - topH - bottomH - margin
    MappingLV.Move(,, lvW, lvH)

    ; Top-row scope text: adapt width
    processTextX := 530
    processTextW := width - processTextX - margin
    ProcessText.Move(,, processTextW)

    ; Bottom row Y: window height minus bottom offset
    btnY := height - bottomH + 5
    statusY := btnY + 5

    ; Bottom buttons
    BtnAddMapping.Move(, btnY)
    BtnEditMapping.Move(, btnY)
    BtnCopyMapping.Move(, btnY)
    BtnDeleteMapping.Move(, btnY)

    ; Admin button: right aligned
    adminX := width - 110 - margin
    BtnRunAsAdmin.Move(adminX, btnY)

    ; Layout status text and detail link
    statusX := 360
    linkW := 75
    linkGap := 8
    linkX := adminX - linkW - linkGap
    statusW := linkX - statusX - 8
    if (statusW < 120)
        statusW := 120

    StatusText.Move(statusX, statusY, statusW)
    StatusDetailLink.Move(linkX, statusY, linkW)

    ; Lightweight bottom redraw: only invalidate child controls to avoid resize flicker
    flags := 0x0001 | 0x0080
    DllCall("RedrawWindow", "ptr", MainGui.Hwnd, "ptr", 0, "ptr", 0, "uint", flags)
}

; Create modal child window (disable main window until it closes)
CreateModalGui(title) {
    modalGui := Gui("+Owner" MainGui.Hwnd " +ToolWindow", title)
    MainGui.Opt("+Disabled")
    modalGui.OnEvent("Close", (*) => DestroyModalGui(modalGui))
    return modalGui
}

; Destroy modal child window and re-enable main window
DestroyModalGui(modalGui) {
    MainGui.Opt("-Disabled")
    modalGui.Destroy()
}

; Centralized detail-link hover state control
SetStatusDetailHover(isHover) {
    if (StatusDetailHovered = isHover)
        return

    global StatusDetailHovered := isHover
    if (isHover) {
        StatusDetailLink.SetFont("c005A9E underline")
        ToolTip(L("GuiMain.Status.DetailTooltip"))
    } else {
        StatusDetailLink.SetFont("c0078D7 underline")
        ToolTip()
    }
}

; Update detail-link hover feedback on mouse move
OnMainMouseMove(wParam, lParam, msg, hwnd) {
    if !StatusHasWarning {
        SetStatusDetailHover(false)
        return
    }

    MouseGetPos(, , &winHwnd, &ctrlHwnd, 2)
    isHover := (winHwnd = MainGui.Hwnd && ctrlHwnd = StatusDetailLink.Hwnd)
    SetStatusDetailHover(isHover)
}

; Use hand cursor when hovering over the detail link
OnMainSetCursor(wParam, lParam, msg, hwnd) {
    if !StatusHasWarning
        return

    MouseGetPos(, , &winHwnd, &ctrlHwnd, 2)
    if (winHwnd = MainGui.Hwnd && ctrlHwnd = StatusDetailLink.Hwnd) {
        static handCursor := DllCall("LoadCursor", "ptr", 0, "ptr", 32649, "ptr") ; IDC_HAND
        DllCall("SetCursor", "ptr", handCursor)
        return true
    }
}

; Show detailed hotkey conflicts and registration errors when clicking status detail
OnStatusTextClick(*) {
    details := BuildStatusDetails(LastReloadResult)
    if (details = "")
        return
    MsgBox(details, APP_NAME, "Icon!")
}

; Detail-popup text from the last reload result ("" when there is nothing to show)
BuildStatusDetails(reloadResult) {
    conflicts := []
    regErrors := []
    if IsObject(reloadResult) {
        conflicts := reloadResult.conflicts
        regErrors := reloadResult.regErrors
    }
    if (conflicts.Length = 0 && regErrors.Length = 0)
        return ""

    details := ""
    if (conflicts.Length > 0) {
        details .= L("GuiMain.Status.ConflictsHeader")
        for _, c in conflicts
            details .= Format(L("GuiMain.Status.ConflictItem"), c.hotkey, c.config1, c.config2)
    }
    if (regErrors.Length > 0) {
        if (details != "")
            details .= "`n"
        details .= L("GuiMain.Status.RegErrorsHeader")
        for _, k in regErrors
            details .= Format(L("GuiMain.Status.RegErrorItem"), k)
    }
    return RTrim(details, "`n")
}

