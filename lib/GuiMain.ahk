; ============================================================================
; AHKeyMap - 主窗口构建模块
; 负责构建主窗口界面
; ============================================================================

; 声明跨文件使用的全局变量
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
; GUI 构建 - 主窗口
; ============================================================================

BuildMainGui() {
    ; 窗口标题：管理员模式时追加标识
    title := APP_NAME " v" APP_VERSION
    if A_IsAdmin
        title .= " [管理员]"
    global MainGui := Gui("+Resize +MinSize720x400", title)
    MainGui.SetFont("s9", "Microsoft YaHei UI")
    MainGui.OnEvent("Close", OnMainClose)
    MainGui.OnEvent("Size", OnMainResize)

    ; --- 配置管理栏（第一行） ---
    MainGui.AddText("x10 y10 w40 h23 +0x200", "配置:")
    global ConfigDDL := MainGui.AddDropDownList("x50 y10 w180 h200 vConfigDDL")
    ConfigDDL.OnEvent("Change", OnConfigSelect)

    global EnabledCB := MainGui.AddCheckbox("x235 y11 w50 h23", "启用")
    EnabledCB.OnEvent("Click", OnToggleEnabled)

    MainGui.AddButton("x290 y9 w50 h25", "新建").OnEvent("Click", OnNewConfig)
    MainGui.AddButton("x345 y9 w50 h25", "复制").OnEvent("Click", OnCopyConfig)
    MainGui.AddButton("x400 y9 w50 h25", "删除").OnEvent("Click", OnDeleteConfig)
    MainGui.AddButton("x455 y9 w70 h25", "作用域").OnEvent("Click", OnChangeProcess)

    ; 作用域文本：宽度自适应，右对齐
    global ProcessText := MainGui.AddText("x530 y10 w180 h23 +0x200", "作用域: 无配置")

    ; --- 映射列表 ---
    global MappingLV := MainGui.AddListView("x10 y45 w700 h360 +Grid -Multi", ["序号", "修饰键", "源按键", "映射目标", "长按连续", "修饰键模式", "触发延迟(ms)", "触发间隔(ms)"])
    MappingLV.OnEvent("DoubleClick", OnEditMapping)

    ; --- 操作按钮栏（底栏，y 坐标在 OnMainResize 中动态调整） ---
    btnY := 415
    statusY := btnY + 5
    global BtnAddMapping := MainGui.AddButton("x10 y" btnY " w80 h30", "新增映射")
    BtnAddMapping.OnEvent("Click", OnAddMapping)
    global BtnEditMapping := MainGui.AddButton("x95 y" btnY " w80 h30", "编辑映射")
    BtnEditMapping.OnEvent("Click", OnEditMapping)
    global BtnCopyMapping := MainGui.AddButton("x180 y" btnY " w80 h30", "复制映射")
    BtnCopyMapping.OnEvent("Click", OnCopyMapping)
    global BtnDeleteMapping := MainGui.AddButton("x265 y" btnY " w80 h30", "删除映射")
    BtnDeleteMapping.OnEvent("Click", OnDeleteMapping)

    ; --- 状态栏（左文本 + 右详情链接） ---
    global StatusText := MainGui.AddText("x360 y" statusY " w150 h23 +0x200 cGray", "已启用 0/0 个配置")
    global StatusDetailLink := MainGui.AddText("x515 y" statusY " w75 h23 +0x200 c0078D7", "查看详情")
    StatusDetailLink.SetFont("underline")
    StatusDetailLink.OnEvent("Click", OnStatusTextClick)
    StatusDetailLink.Opt("+Hidden")

    ; 详情链接交互反馈：悬停高亮 + 手型指针
    OnMessage(0x0200, OnMainMouseMove)
    OnMessage(0x0020, OnMainSetCursor)

    ; --- 管理员提权按钮 ---
    global BtnRunAsAdmin := MainGui.AddButton("x600 y" btnY " w110 h30", "以管理员重启")
    BtnRunAsAdmin.OnEvent("Click", OnRunAsAdmin)
    if A_IsAdmin
        BtnRunAsAdmin.Enabled := false

    ; 托盘菜单
    tray := A_TrayMenu
    tray.Delete()
    tray.Add("显示主窗口", OnTrayShow)
    tray.Add()
    tray.Add("开机自启", OnTrayAutoStartToggle)
    if IsAutoStartEnabled()
        tray.Check("开机自启")
    tray.Add()
    adminTrayItem := "以管理员身份重启"
    tray.Add(adminTrayItem, OnRunAsAdmin)
    if A_IsAdmin
        tray.Disable(adminTrayItem)
    tray.Add()
    tray.Add("退出", OnTrayExit)
    tray.Default := "显示主窗口"
}

; 主窗口大小调整
; 三行布局：顶栏固定(h45) | ListView 自适应 | 底栏固定(h45)
OnMainResize(thisGui, minMax, width, height) {
    if (minMax = -1)
        return

    ; 布局常量
    topH := 45      ; 顶栏区域高度（y=0 到 ListView 起始）
    bottomH := 45   ; 底栏区域高度
    margin := 10    ; 水平边距

    ; ListView：自适应填充中间区域
    lvW := width - margin * 2
    lvH := height - topH - bottomH - margin
    MappingLV.Move(,, lvW, lvH)

    ; 顶栏作用域文本：宽度自适应
    processTextX := 530
    processTextW := width - processTextX - margin
    ProcessText.Move(,, processTextW)

    ; 底栏 y 坐标：窗口高 - 底栏偏移
    btnY := height - bottomH + 5
    statusY := btnY + 5

    ; 底栏按钮
    BtnAddMapping.Move(, btnY)
    BtnEditMapping.Move(, btnY)
    BtnCopyMapping.Move(, btnY)
    BtnDeleteMapping.Move(, btnY)

    ; 管理员按钮：右对齐
    adminX := width - 110 - margin
    BtnRunAsAdmin.Move(adminX, btnY)

    ; 状态栏与详情入口布局
    statusX := 360
    linkW := 75
    linkGap := 8
    linkX := adminX - linkW - linkGap
    statusW := linkX - statusX - 8
    if (statusW < 120)
        statusW := 120

    StatusText.Move(statusX, statusY, statusW)
    StatusDetailLink.Move(linkX, statusY, linkW)

    ; 轻量重绘底栏：仅失效重绘子控件，避免强制擦除带来的 resize 闪烁
    flags := 0x0001 | 0x0080
    DllCall("RedrawWindow", "ptr", MainGui.Hwnd, "ptr", 0, "ptr", 0, "uint", flags)
}

; 创建模态子窗口（禁用主窗口，子窗口关闭时自动恢复）
CreateModalGui(title) {
    modalGui := Gui("+Owner" MainGui.Hwnd " +ToolWindow", title)
    MainGui.Opt("+Disabled")
    modalGui.OnEvent("Close", (*) => DestroyModalGui(modalGui))
    return modalGui
}

; 销毁模态子窗口并恢复主窗口
DestroyModalGui(modalGui) {
    MainGui.Opt("-Disabled")
    modalGui.Destroy()
}

; 统一控制详情链接悬停状态
SetStatusDetailHover(isHover) {
    if (StatusDetailHovered = isHover)
        return

    global StatusDetailHovered := isHover
    if (isHover) {
        StatusDetailLink.SetFont("c005A9E underline")
        ToolTip("点击查看冲突与注册失败详情")
    } else {
        StatusDetailLink.SetFont("c0078D7 underline")
        ToolTip()
    }
}

; 鼠标移动时更新详情链接的悬停反馈
OnMainMouseMove(wParam, lParam, msg, hwnd) {
    if !StatusHasWarning {
        SetStatusDetailHover(false)
        return
    }

    MouseGetPos(, , &winHwnd, &ctrlHwnd, 2)
    isHover := (winHwnd = MainGui.Hwnd && ctrlHwnd = StatusDetailLink.Hwnd)
    SetStatusDetailHover(isHover)
}

; 详情链接悬停时使用手型指针
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

; 点击状态栏详情时展示热键冲突与注册失败的详细信息
OnStatusTextClick(*) {
    if (HotkeyConflicts.Length = 0 && HotkeyRegErrors.Length = 0)
        return
    details := ""
    if (HotkeyConflicts.Length > 0) {
        details .= "热键冲突：`n"
        for _, c in HotkeyConflicts
            details .= "  " c.hotkey "（" c.config1 " / " c.config2 "）`n"
    }
    if (HotkeyRegErrors.Length > 0) {
        if (details != "")
            details .= "`n"
        details .= "注册失败：`n"
        for _, k in HotkeyRegErrors
            details .= "  " k "`n"
    }
    MsgBox(RTrim(details, "`n"), APP_NAME, "Icon!")
}

