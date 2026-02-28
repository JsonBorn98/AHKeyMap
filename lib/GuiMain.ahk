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

; ============================================================================
; GUI 构建 - 主窗口
; ============================================================================

BuildMainGui() {
    ; 窗口标题：管理员模式时追加标识
    title := APP_NAME " v" APP_VERSION
    if A_IsAdmin
        title .= " [管理员]"
    global MainGui := Gui("+Resize", title)
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

    global ProcessText := MainGui.AddText("x530 y10 w180 h23 +0x200", "作用域: 无配置")

    ; --- 映射列表 ---
    global MappingLV := MainGui.AddListView("x10 y45 w700 h360 +Grid -Multi", ["序号", "修饰键", "源按键", "映射目标", "长按连续", "修饰键模式", "触发延迟(ms)", "触发间隔(ms)"])
    MappingLV.OnEvent("DoubleClick", OnEditMapping)

    ; --- 操作按钮栏 ---
    btnY := 415
    MainGui.AddButton("x10 y" btnY " w80 h30", "新增映射").OnEvent("Click", OnAddMapping)
    MainGui.AddButton("x95 y" btnY " w80 h30", "编辑映射").OnEvent("Click", OnEditMapping)
    MainGui.AddButton("x180 y" btnY " w80 h30", "复制映射").OnEvent("Click", OnCopyMapping)
    MainGui.AddButton("x265 y" btnY " w80 h30", "删除映射").OnEvent("Click", OnDeleteMapping)

    ; --- 状态栏 ---
    global StatusText := MainGui.AddText("x360 y" btnY + 5 " w230 h23 +0x200 cGray", "已启用 0/0 个配置")

    ; --- 管理员提权按钮 ---
    adminBtn := MainGui.AddButton("x600 y" btnY " w110 h30", "以管理员重启")
    adminBtn.OnEvent("Click", OnRunAsAdmin)
    if A_IsAdmin
        adminBtn.Enabled := false

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
OnMainResize(thisGui, minMax, width, height) {
    if (minMax = -1)
        return
    MappingLV.Move(,, width - 20, height - 140)
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
