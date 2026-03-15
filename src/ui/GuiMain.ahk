; ============================================================================
; AHKeyMap - Main window construction module
; Builds the main window UI
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
global HotkeyConflicts
global HotkeyRegErrors

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

    tray.Add(adminTrayItem, OnRunAsAdmin)
    if A_IsAdmin
        tray.Disable(adminTrayItem)
    tray.Add()
    tray.Add(exitLabel, OnTrayExit)
    tray.Default := showMainLabel
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
    if (HotkeyConflicts.Length = 0 && HotkeyRegErrors.Length = 0)
        return

    details := ""
    if (HotkeyConflicts.Length > 0) {
        details .= L("GuiMain.Status.ConflictsHeader")
        for _, c in HotkeyConflicts
            details .= Format(L("GuiMain.Status.ConflictItem"), c.hotkey, c.config1, c.config2)
    }
    if (HotkeyRegErrors.Length > 0) {
        if (details != "")
            details .= "`n"
        details .= L("GuiMain.Status.RegErrorsHeader")
        for _, k in HotkeyRegErrors
            details .= Format(L("GuiMain.Status.RegErrorItem"), k)
    }
    MsgBox(RTrim(details, "`n"), APP_NAME, "Icon!")
}

