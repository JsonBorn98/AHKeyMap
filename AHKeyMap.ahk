; ============================================================================
; AHKeyMap - AHKv2 按键映射工具
; 支持多配置管理、多进程绑定、按键捕获、组合键映射、长按连续触发
; 支持自定义修饰键（含鼠标按键）、滚轮映射、状态追踪式组合键
; 支持多配置同时生效、三态进程作用域（全局/仅指定/排除指定）
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

;@Ahk2Exe-SetName AHKeyMap
;@Ahk2Exe-SetDescription AHKeyMap - 按键映射工具
;@Ahk2Exe-SetVersion 2.0.0
;@Ahk2Exe-SetCopyright Copyright (c) 2026
;@Ahk2Exe-SetMainIcon icon.ico

; ============================================================================
; 全局变量
; ============================================================================
global APP_NAME := "AHKeyMap"
global APP_VERSION := "2.0"
global SCRIPT_DIR := A_ScriptDir
global CONFIG_DIR := SCRIPT_DIR "\configs"
global STATE_FILE := CONFIG_DIR "\_state.ini"

; 多配置并存：所有已加载的配置
; 每项为 Map: name, file, processMode, process, processList, excludeProcess, excludeProcessList, mappings, enabled, checker
global AllConfigs := []

; 当前 GUI 编辑的配置（仅用于界面显示/编辑）
global CurrentConfigName := ""
global CurrentConfigFile := ""
global CurrentProcessMode := "global"  ; "global" / "include" / "exclude"
global CurrentProcess := ""            ; 原始字符串 "a.exe|b.exe"（include 模式）
global CurrentProcessList := []        ; 解析后的数组 ["a.exe", "b.exe"]
global CurrentExcludeProcess := ""     ; 原始字符串（exclude 模式）
global CurrentExcludeProcessList := [] ; 解析后的数组
global CurrentConfigEnabled := true    ; 当前配置是否启用
global Mappings := []                  ; 当前配置的映射数组，每项为 Map 对象
global ActiveHotkeys := []             ; 当前已注册的热键列表（全局，所有配置共享）
global IsCapturing := false            ; 是否正在捕获按键
global CaptureTarget := ""             ; 捕获目标："source" / "target" / "modifier"
global CaptureCallback := ""           ; 捕获完成后的回调

; GUI 控件引用
global MainGui := ""
global ConfigDDL := ""
global EnabledCB := ""               ; 启用/禁用复选框
global ProcessText := ""
global StatusText := ""              ; 状态栏：显示已启用配置数
global MappingLV := ""
global EditGui := ""
global EditModifierEdit := ""
global EditSourceEdit := ""
global EditTargetEdit := ""
global EditHoldRepeatCB := ""
global EditDelayEdit := ""
global EditIntervalEdit := ""
global EditPassthroughCB := ""
global EditingIndex := 0             ; 0=新增, >0=编辑第N项
global CaptureGui := ""
global CaptureDisplayText := ""      ; 捕获窗口实时显示控件
global CaptureTimer := ""            ; 捕获轮询定时器引用
global CaptureKeys := []             ; 当前/最后一次按住的键名数组
global CaptureHadKeys := false       ; 是否曾经有键被按下
global CaptureMouseKeys := Map()     ; 当前按住的鼠标键 (名称 -> true)
global HoldTimers := Map()           ; 长按定时器状态存储
global ComboFiredState := Map()      ; 状态追踪：修饰键按住期间是否触发过组合
global PassthroughModKeys := Map()   ; 已注册的状态追踪式修饰键 Up 钩子
global InterceptModKeys := Map()     ; 已注册的拦截式修饰键恢复热键
global PassthroughHandlers := Map()  ; 状态追踪式：sourceKey -> [{modKey, targetKey, holdRepeat, ...}]
global PassthroughSourceRegistered := Map()  ; 已注册的状态追踪式 sourceKey 热键
global AllProcessCheckers := []      ; 所有配置的 HotIf 闭包引用（防止被 GC）

; ============================================================================
; 启动入口
; ============================================================================
StartApp()

StartApp() {
    ; 确保配置目录存在
    if !DirExist(CONFIG_DIR)
        DirCreate(CONFIG_DIR)

    ; 加载上次使用的配置（用于 GUI 显示）
    lastConfig := ""
    if FileExist(STATE_FILE)
        lastConfig := IniRead(STATE_FILE, "State", "LastConfig", "")

    ; 构建主界面
    BuildMainGui()

    ; 加载所有配置到 AllConfigs 并注册已启用配置的热键
    LoadAllConfigs()

    ; 刷新配置下拉列表（仅 GUI 显示）
    RefreshConfigList(lastConfig)

    ; 注册所有已启用配置的热键
    ReloadAllHotkeys()

    ; 显示主窗口
    MainGui.Show("w720 h500")
}

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
        mapping["RepeatDelay"] := Integer(IniRead(configFile, section, "RepeatDelay", "300"))
        mapping["RepeatInterval"] := Integer(IniRead(configFile, section, "RepeatInterval", "50"))
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
        Mappings := []
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

; 格式化进程作用域为显示文本
FormatProcessDisplay(processMode, process, excludeProcess) {
    if (processMode = "include") {
        list := ParseProcessList(process)
        if (list.Length = 0)
            return "作用域: 全局"
        if (list.Length = 1)
            return "作用域: 仅 " list[1]
        return "作用域: 仅 " list[1] " 等" list.Length "个"
    } else if (processMode = "exclude") {
        list := ParseProcessList(excludeProcess)
        if (list.Length = 0)
            return "作用域: 全局"
        if (list.Length = 1)
            return "作用域: 排除 " list[1]
        return "作用域: 排除 " list[1] " 等" list.Length "个"
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
    StatusText.Value := "已启用 " enabledCount "/" totalCount " 个配置"
}

; 加载指定配置到 GUI 编辑区域（不影响热键注册）
LoadConfigToGui(configName) {
    global CurrentConfigName := configName
    global CurrentConfigFile := CONFIG_DIR "\" configName ".ini"
    global Mappings := []

    idx := FindConfigIndex(configName)
    if (idx = 0)
        return

    cfg := AllConfigs[idx]
    global CurrentProcessMode := cfg["processMode"]
    global CurrentProcess := cfg["process"]
    global CurrentProcessList := cfg["processList"]
    global CurrentExcludeProcess := cfg["excludeProcess"]
    global CurrentExcludeProcessList := cfg["excludeProcessList"]
    global CurrentConfigEnabled := cfg["enabled"]

    ; 复制映射数据到 GUI 编辑用的 Mappings
    global Mappings := []
    for _, m in cfg["mappings"] {
        newM := Map()
        for k, v in m
            newM[k] := v
        Mappings.Push(newM)
    }

    ProcessText.Value := FormatProcessDisplay(CurrentProcessMode, CurrentProcess, CurrentExcludeProcess)
    EnabledCB.Value := CurrentConfigEnabled
    EnabledCB.Enabled := true

    RefreshMappingLV()

    ; 保存最后查看的配置
    IniWrite(configName, STATE_FILE, "State", "LastConfig")
}

; 保存当前配置到文件
SaveConfig() {
    if (CurrentConfigName = "" || CurrentConfigFile = "")
        return

    ; 删除旧文件重写
    if FileExist(CurrentConfigFile)
        FileDelete(CurrentConfigFile)

    IniWrite(CurrentConfigName, CurrentConfigFile, "Meta", "Name")
    IniWrite(CurrentProcessMode, CurrentConfigFile, "Meta", "ProcessMode")
    IniWrite(CurrentProcess, CurrentConfigFile, "Meta", "Process")
    IniWrite(CurrentExcludeProcess, CurrentConfigFile, "Meta", "ExcludeProcess")

    for idx, mapping in Mappings {
        section := "Mapping" idx
        IniWrite(mapping["ModifierKey"], CurrentConfigFile, section, "ModifierKey")
        IniWrite(mapping["SourceKey"], CurrentConfigFile, section, "SourceKey")
        IniWrite(mapping["TargetKey"], CurrentConfigFile, section, "TargetKey")
        IniWrite(mapping["HoldRepeat"], CurrentConfigFile, section, "HoldRepeat")
        IniWrite(mapping["RepeatDelay"], CurrentConfigFile, section, "RepeatDelay")
        IniWrite(mapping["RepeatInterval"], CurrentConfigFile, section, "RepeatInterval")
        IniWrite(mapping["PassthroughMod"], CurrentConfigFile, section, "PassthroughMod")
    }

    ; 同步到 AllConfigs 并保存启用状态
    SyncCurrentToAllConfigs()
    SaveEnabledStates()
}

; 保存所有配置的启用状态到 _state.ini
SaveEnabledStates() {
    for _, cfg in AllConfigs {
        IniWrite(cfg["enabled"] ? "1" : "0", STATE_FILE, "EnabledConfigs", cfg["name"])
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
        MappingLV.Add(""
            , idx
            , modDisplay
            , KeyToDisplay(mapping["SourceKey"])
            , KeyToDisplay(mapping["TargetKey"])
            , holdText
            , ptText
            , mapping["RepeatDelay"]
            , mapping["RepeatInterval"])
    }
    ; 自动调整列宽
    loop 8
        MappingLV.ModifyCol(A_Index, "AutoHdr")
}

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
    global StatusText := MainGui.AddText("x360 y" btnY + 5 " w180 h23 +0x200 cGray", "已启用 0/0 个配置")

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

; ============================================================================
; GUI 事件处理 - 配置管理
; ============================================================================

OnConfigSelect(ctrl, *) {
    selected := ctrl.Text
    if (selected != "" && selected != CurrentConfigName) {
        LoadConfigToGui(selected)
    } else if (selected != "" && CurrentConfigName = "") {
        LoadConfigToGui(selected)
    }
}

; 启用/禁用复选框
OnToggleEnabled(ctrl, *) {
    if (CurrentConfigName = "")
        return
    global CurrentConfigEnabled := ctrl.Value ? true : false
    SyncCurrentToAllConfigs()
    SaveEnabledStates()
    ReloadAllHotkeys()
    UpdateStatusText()
}

OnNewConfig(*) {
    newGui := CreateModalGui("新建配置")
    newGui.SetFont("s9", "Microsoft YaHei UI")

    newGui.AddText("x10 y10 w80 h23 +0x200", "配置名称:")
    nameEdit := newGui.AddEdit("x90 y10 w250 h23 vConfigName")

    ; 三态进程模式
    newGui.AddGroupBox("x10 y42 w330 h175", "作用域")
    globalRadio := newGui.AddRadio("x20 y62 w310 h20 vProcessMode Checked", "全局生效")
    includeRadio := newGui.AddRadio("x20 y85 w310 h20", "仅指定进程生效")
    excludeRadio := newGui.AddRadio("x20 y108 w310 h20", "排除指定进程")

    newGui.AddText("x20 y133 w60 h23 +0x200", "进程列表:")
    procEdit := newGui.AddEdit("x85 y133 w195 h70 vProcName Multi")
    procEdit.Enabled := false
    procPickBtn := newGui.AddButton("x285 y133 w45 h25", "选择")
    procPickBtn.OnEvent("Click", (*) => ShowProcessPicker(procEdit, true))
    procPickBtn.Enabled := false

    ; 单选按钮切换时启用/禁用进程编辑
    globalRadio.OnEvent("Click", (*) => (procEdit.Enabled := false, procPickBtn.Enabled := false))
    includeRadio.OnEvent("Click", (*) => (procEdit.Enabled := true, procPickBtn.Enabled := true))
    excludeRadio.OnEvent("Click", (*) => (procEdit.Enabled := true, procPickBtn.Enabled := true))

    newGui.AddButton("x100 y225 w80 h28", "确定").OnEvent("Click", OnNewConfigOK.Bind(newGui))
    newGui.AddButton("x190 y225 w80 h28", "取消").OnEvent("Click", (*) => DestroyModalGui(newGui))

    newGui.Show("w350 h265")
}

OnNewConfigOK(newGui, *) {
    configName := Trim(newGui["ConfigName"].Value)

    if (configName = "") {
        MsgBox("请输入配置名称", APP_NAME, "Icon!")
        return
    }

    configFile := CONFIG_DIR "\" configName ".ini"
    if FileExist(configFile) {
        MsgBox("配置 '" configName "' 已存在", APP_NAME, "Icon!")
        return
    }

    ; 确定进程模式
    processMode := "global"
    submitted := newGui.Submit(false)
    if (submitted.ProcessMode = 2)
        processMode := "include"
    else if (submitted.ProcessMode = 3)
        processMode := "exclude"

    ; 解析进程列表
    rawText := newGui["ProcName"].Value
    procStr := ""
    loop parse rawText, "`n", "`r" {
        trimmed := Trim(A_LoopField)
        if (trimmed != "") {
            if (procStr != "")
                procStr .= "|"
            procStr .= trimmed
        }
    }

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

    ; 默认启用新配置
    IniWrite("1", STATE_FILE, "EnabledConfigs", configName)

    DestroyModalGui(newGui)

    ; 重新加载所有配置
    LoadAllConfigs()
    RefreshConfigList(configName)
    ReloadAllHotkeys()
}

; 复制配置
OnCopyConfig(*) {
    if (CurrentConfigName = "") {
        MsgBox("没有选中的配置", APP_NAME, "Icon!")
        return
    }

    copyGui := CreateModalGui("复制配置")
    copyGui.SetFont("s9", "Microsoft YaHei UI")

    copyGui.AddText("x10 y10 w80 h23 +0x200", "新名称:")
    defaultName := CurrentConfigName "_copy"
    nameEdit := copyGui.AddEdit("x90 y10 w250 h23 vNewName", defaultName)

    copyGui.AddButton("x110 y48 w80 h28", "确定").OnEvent("Click", OnCopyConfigOK.Bind(copyGui))
    copyGui.AddButton("x200 y48 w80 h28", "取消").OnEvent("Click", (*) => DestroyModalGui(copyGui))

    copyGui.Show("w350 h88")
}

OnCopyConfigOK(copyGui, *) {
    newName := Trim(copyGui["NewName"].Value)

    if (newName = "") {
        MsgBox("请输入配置名称", APP_NAME, "Icon!")
        return
    }

    newFile := CONFIG_DIR "\" newName ".ini"
    if FileExist(newFile) {
        MsgBox("配置 '" newName "' 已存在", APP_NAME, "Icon!")
        return
    }

    ; 复制当前配置文件
    if FileExist(CurrentConfigFile)
        FileCopy(CurrentConfigFile, newFile)

    ; 修改副本中的 Name
    IniWrite(newName, newFile, "Meta", "Name")

    ; 默认启用
    IniWrite("1", STATE_FILE, "EnabledConfigs", newName)

    DestroyModalGui(copyGui)

    ; 重新加载所有配置
    LoadAllConfigs()
    RefreshConfigList(newName)
    ReloadAllHotkeys()
}

OnDeleteConfig(*) {
    if (CurrentConfigName = "") {
        MsgBox("没有选中的配置", APP_NAME, "Icon!")
        return
    }

    result := MsgBox("确定要删除配置 '" CurrentConfigName "' 吗？", APP_NAME, "YesNo Icon?")
    if (result = "Yes") {
        if FileExist(CurrentConfigFile)
            FileDelete(CurrentConfigFile)

        ; 从 AllConfigs 中移除
        idx := FindConfigIndex(CurrentConfigName)
        if (idx > 0)
            AllConfigs.RemoveAt(idx)

        global CurrentConfigName := ""
        global CurrentConfigFile := ""
        global Mappings := []

        ReloadAllHotkeys()
        RefreshConfigList()
    }
}

OnChangeProcess(*) {
    if (CurrentConfigName = "") {
        MsgBox("没有选中的配置", APP_NAME, "Icon!")
        return
    }

    changeGui := CreateModalGui("修改作用域")
    changeGui.SetFont("s9", "Microsoft YaHei UI")

    ; 三态单选
    changeGui.AddGroupBox("x10 y5 w370 h210", "作用域模式")
    globalRadio := changeGui.AddRadio("x20 y25 w350 h20 vProcessMode", "全局生效")
    includeRadio := changeGui.AddRadio("x20 y48 w350 h20", "仅指定进程生效")
    excludeRadio := changeGui.AddRadio("x20 y71 w350 h20", "排除指定进程")

    ; 根据当前模式选中
    if (CurrentProcessMode = "include")
        includeRadio.Value := 1
    else if (CurrentProcessMode = "exclude")
        excludeRadio.Value := 1
    else
        globalRadio.Value := 1

    changeGui.AddText("x20 y98 w60 h23 +0x200", "进程列表:")
    changeGui.AddText("x20 y120 w350 h16 cGray", "（每行一个进程名）")

    ; 根据模式显示对应的进程列表
    displayProc := ""
    if (CurrentProcessMode = "include")
        displayProc := StrReplace(CurrentProcess, "|", "`n")
    else if (CurrentProcessMode = "exclude")
        displayProc := StrReplace(CurrentExcludeProcess, "|", "`n")

    procEdit := changeGui.AddEdit("x20 y138 w290 h65 vProcName Multi", displayProc)
    procPickBtn2 := changeGui.AddButton("x315 y138 w55 h25", "选择")
    procPickBtn2.OnEvent("Click", (*) => ShowProcessPicker(procEdit, true))

    ; 全局模式下禁用进程编辑
    isGlobal := (CurrentProcessMode = "global")
    procEdit.Enabled := !isGlobal
    procPickBtn2.Enabled := !isGlobal

    globalRadio.OnEvent("Click", (*) => (procEdit.Enabled := false, procPickBtn2.Enabled := false))
    includeRadio.OnEvent("Click", (*) => (procEdit.Enabled := true, procPickBtn2.Enabled := true))
    excludeRadio.OnEvent("Click", (*) => (procEdit.Enabled := true, procPickBtn2.Enabled := true))

    changeGui.AddButton("x100 y222 w80 h28", "确定").OnEvent("Click", OnChangeProcessOK.Bind(changeGui))
    changeGui.AddButton("x200 y222 w80 h28", "取消").OnEvent("Click", (*) => DestroyModalGui(changeGui))

    changeGui.Show("w390 h260")
}

OnChangeProcessOK(changeGui, *) {
    ; 确定进程模式
    submitted := changeGui.Submit(false)
    processMode := "global"
    if (submitted.ProcessMode = 2)
        processMode := "include"
    else if (submitted.ProcessMode = 3)
        processMode := "exclude"

    ; 解析进程列表
    rawText := changeGui["ProcName"].Value
    procStr := ""
    loop parse rawText, "`n", "`r" {
        trimmed := Trim(A_LoopField)
        if (trimmed != "") {
            if (procStr != "")
                procStr .= "|"
            procStr .= trimmed
        }
    }

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

    ProcessText.Value := FormatProcessDisplay(CurrentProcessMode, CurrentProcess, CurrentExcludeProcess)

    SaveConfig()
    ReloadAllHotkeys()
    changeGui.Destroy()
}

; ============================================================================
; GUI 事件处理 - 映射管理
; ============================================================================

OnAddMapping(*) {
    if (CurrentConfigName = "") {
        MsgBox("请先选择或新建一个配置", APP_NAME, "Icon!")
        return
    }
    global EditingIndex := 0
    ShowEditMappingGui()
}

OnEditMapping(ctrl, rowNum := 0, *) {
    if (CurrentConfigName = "") {
        MsgBox("请先选择或新建一个配置", APP_NAME, "Icon!")
        return
    }

    if (ctrl = MappingLV) {
        if (rowNum = 0)
            return
        global EditingIndex := rowNum
    } else {
        rowNum := MappingLV.GetNext(0, "F")
        if (rowNum = 0) {
            MsgBox("请先选中一个映射", APP_NAME, "Icon!")
            return
        }
        global EditingIndex := rowNum
    }
    ShowEditMappingGui()
}

OnCopyMapping(*) {
    if (CurrentConfigName = "") {
        MsgBox("请先选择或新建一个配置", APP_NAME, "Icon!")
        return
    }

    rowNum := MappingLV.GetNext(0, "F")
    if (rowNum = 0) {
        MsgBox("请先选中一个映射", APP_NAME, "Icon!")
        return
    }

    srcMapping := Mappings[rowNum]
    newMapping := Map()
    for key, val in srcMapping
        newMapping[key] := val
    Mappings.Push(newMapping)

    SaveConfig()
    RefreshMappingLV()
    ReloadAllHotkeys()

    newIdx := Mappings.Length
    MappingLV.Modify(newIdx, "Select Focus Vis")
    global EditingIndex := newIdx
    ShowEditMappingGui()
}

OnDeleteMapping(*) {
    if (CurrentConfigName = "") {
        MsgBox("请先选择或新建一个配置", APP_NAME, "Icon!")
        return
    }

    rowNum := MappingLV.GetNext(0, "F")
    if (rowNum = 0) {
        MsgBox("请先选中一个映射", APP_NAME, "Icon!")
        return
    }

    result := MsgBox("确定要删除这个映射吗？", APP_NAME, "YesNo Icon?")
    if (result = "Yes") {
        Mappings.RemoveAt(rowNum)
        SaveConfig()
        RefreshMappingLV()
        ReloadAllHotkeys()
    }
}

; ============================================================================
; 映射编辑弹窗
; ============================================================================

ShowEditMappingGui() {
    global EditGui := Gui("+Owner" MainGui.Hwnd " +ToolWindow", EditingIndex > 0 ? "编辑映射" : "新增映射")
    EditGui.SetFont("s9", "Microsoft YaHei UI")

    ; 修饰键（新增行）
    EditGui.AddText("x10 y10 w70 h23 +0x200", "修饰键:")
    global EditModifierEdit := EditGui.AddEdit("x80 y10 w180 h23 vModifierKey ReadOnly")
    EditGui.AddButton("x265 y9 w65 h25", "捕获").OnEvent("Click", OnCaptureModifier)
    EditGui.AddButton("x335 y9 w50 h25", "清除").OnEvent("Click", OnClearModifier)

    ; 源按键
    EditGui.AddText("x10 y45 w70 h23 +0x200", "源按键:")
    global EditSourceEdit := EditGui.AddEdit("x80 y45 w180 h23 vSourceKey ReadOnly")
    EditGui.AddButton("x265 y44 w65 h25", "捕获").OnEvent("Click", OnCaptureSource)

    ; 映射目标
    EditGui.AddText("x10 y80 w70 h23 +0x200", "映射目标:")
    global EditTargetEdit := EditGui.AddEdit("x80 y80 w180 h23 vTargetKey ReadOnly")
    EditGui.AddButton("x265 y79 w65 h25", "捕获").OnEvent("Click", OnCaptureTarget)

    ; 长按连续触发
    global EditHoldRepeatCB := EditGui.AddCheckbox("x10 y115 w150 h23 vHoldRepeat", "长按连续触发")
    EditHoldRepeatCB.OnEvent("Click", OnHoldRepeatToggle)

    ; 触发延迟
    EditGui.AddText("x10 y145 w100 h23 +0x200", "触发延迟(ms):")
    global EditDelayEdit := EditGui.AddEdit("x110 y145 w80 h23 vRepeatDelay Number")
    EditDelayEdit.Value := "300"

    ; 触发间隔
    EditGui.AddText("x200 y145 w100 h23 +0x200", "触发间隔(ms):")
    global EditIntervalEdit := EditGui.AddEdit("x300 y145 w80 h23 vRepeatInterval Number")
    EditIntervalEdit.Value := "50"

    ; 保留修饰键原始功能
    global EditPassthroughCB := EditGui.AddCheckbox("x10 y175 w370 h23 vPassthroughMod", "保留修饰键原始功能（手势/拖拽等不受影响）")

    ; 如果是编辑模式，填入现有数据
    if (EditingIndex > 0 && EditingIndex <= Mappings.Length) {
        m := Mappings[EditingIndex]
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

    ; 根据状态控制控件可用性
    OnHoldRepeatToggle(EditHoldRepeatCB, "")
    UpdatePassthroughState()

    ; 按钮
    EditGui.AddButton("x100 y210 w80 h28", "确定").OnEvent("Click", OnEditMappingOK)
    EditGui.AddButton("x190 y210 w80 h28", "取消").OnEvent("Click", (*) => EditGui.Destroy())

    EditGui.OnEvent("Close", (*) => EditGui.Destroy())
    EditGui.Show("w395 h250")
}

UpdatePassthroughState() {
    ; 保留修饰键原始功能 仅在修饰键非空时可用
    hasModifier := EditModifierEdit.ahkKey != ""
    EditPassthroughCB.Enabled := hasModifier
    if !hasModifier
        EditPassthroughCB.Value := 0
}

OnClearModifier(*) {
    EditModifierEdit.Value := ""
    EditModifierEdit.ahkKey := ""
    UpdatePassthroughState()
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
        MsgBox("请设置源按键", APP_NAME, "Icon!")
        return
    }
    if (targetAhk = "") {
        MsgBox("请设置映射目标", APP_NAME, "Icon!")
        return
    }

    mapping := Map()
    mapping["ModifierKey"] := modifierAhk
    mapping["SourceKey"] := sourceAhk
    mapping["TargetKey"] := targetAhk
    mapping["HoldRepeat"] := EditHoldRepeatCB.Value ? 1 : 0
    mapping["RepeatDelay"] := EditDelayEdit.Value != "" ? Integer(EditDelayEdit.Value) : 300
    mapping["RepeatInterval"] := EditIntervalEdit.Value != "" ? Integer(EditIntervalEdit.Value) : 50
    mapping["PassthroughMod"] := EditPassthroughCB.Value ? 1 : 0

    if (EditingIndex > 0 && EditingIndex <= Mappings.Length) {
        Mappings[EditingIndex] := mapping
    } else {
        Mappings.Push(mapping)
    }

    SaveConfig()
    RefreshMappingLV()
    ReloadAllHotkeys()
    EditGui.Destroy()
}

; ============================================================================
; 按键捕获（松开时确认机制）
; ============================================================================

; 所有需要轮询的键名列表
global ALL_KEY_NAMES := BuildKeyNameList()

BuildKeyNameList() {
    keys := []
    ; 修饰键（左右分开检测，显示时归一化）
    for k in ["LCtrl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin"]
        keys.Push(k)
    ; 字母键
    loop 26
        keys.Push(Chr(64 + A_Index))  ; A-Z
    ; 数字键
    loop 10
        keys.Push(String(A_Index - 1))  ; 0-9
    ; 功能键（仅 F1-F12，F13-F24 在多数键盘上不存在，GetKeyState 可能误报）
    loop 12
        keys.Push("F" A_Index)  ; F1-F12
    ; 特殊键
    for k in ["Space", "Enter", "Tab", "Backspace", "Delete", "Insert",
              "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right",
              "PrintScreen", "ScrollLock", "Pause", "CapsLock", "NumLock",
              "Escape", "AppsKey",
              "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
              "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
              "NumpadDot", "NumpadDiv", "NumpadMult", "NumpadAdd", "NumpadSub", "NumpadEnter"]
        keys.Push(k)
    ; 符号键（使用 VK 名称，避免扫描码在不同键盘布局下误报）
    for k in ["vkBA", "vkBB", "vkBC", "vkBD", "vkBE", "vkBF", "vkC0",
              "vkDB", "vkDC", "vkDD", "vkDE"]
        keys.Push(k)
    return keys
}

; VK 码到可读名称的映射
VkToDisplayName(vkName) {
    static vkMap := Map(
        "vkBA", ";",
        "vkBB", "=",
        "vkBC", ",",
        "vkBD", "-",
        "vkBE", ".",
        "vkBF", "/",
        "vkC0", "``",
        "vkDB", "[",
        "vkDC", "\",
        "vkDD", "]",
        "vkDE", "'"
    )
    if vkMap.Has(vkName)
        return vkMap[vkName]
    return vkName
}

; 修饰键归一化映射
IsModifierKey(keyName) {
    return (keyName = "LCtrl" || keyName = "RCtrl"
         || keyName = "LShift" || keyName = "RShift"
         || keyName = "LAlt" || keyName = "RAlt"
         || keyName = "LWin" || keyName = "RWin")
}

; 将修饰键名归一化为 AHK 前缀符号
ModifierToPrefix(keyName) {
    if (keyName = "LCtrl" || keyName = "RCtrl")
        return "^"
    if (keyName = "LShift" || keyName = "RShift")
        return "+"
    if (keyName = "LAlt" || keyName = "RAlt")
        return "!"
    if (keyName = "LWin" || keyName = "RWin")
        return "#"
    return ""
}

; 将修饰键名归一化为显示名
ModifierToDisplayName(keyName) {
    if (keyName = "LCtrl" || keyName = "RCtrl")
        return "Ctrl"
    if (keyName = "LShift" || keyName = "RShift")
        return "Shift"
    if (keyName = "LAlt" || keyName = "RAlt")
        return "Alt"
    if (keyName = "LWin" || keyName = "RWin")
        return "Win"
    return keyName
}

OnCaptureModifier(*) {
    global CaptureTarget := "modifier"
    StartCapture()
}

OnCaptureSource(*) {
    global CaptureTarget := "source"
    StartCapture()
}

OnCaptureTarget(*) {
    global CaptureTarget := "target"
    StartCapture()
}

StartCapture() {
    global IsCapturing := false  ; 先不启用，等延迟后再启用
    global CaptureKeys := []
    global CaptureHadKeys := false
    global CaptureMouseKeys := Map()

    ; 创建捕获提示窗口（带实时显示区域）
    global CaptureGui := Gui("+AlwaysOnTop +ToolWindow -SysMenu", "按键捕获")
    CaptureGui.SetFont("s11", "Microsoft YaHei UI")
    global CaptureDisplayText := CaptureGui.AddText("x20 y10 w300 h30 Center", "请按下按键组合...")
    CaptureGui.SetFont("s9", "Microsoft YaHei UI")
    CaptureGui.AddText("x20 y45 w300 h20 Center cGray", "松开所有键后自动确认，按 Esc 取消")
    CaptureGui.Show("w340 h75")

    ; 延迟 200ms 后再真正启用捕获，避免捕获到点击"捕获"按钮的鼠标事件
    SetTimer(StartCaptureDelayed, -200)
}

StartCaptureDelayed() {
    ; 如果捕获窗口已被关闭（用户可能在延迟期间操作了），直接返回
    if (CaptureGui = "")
        return

    global IsCapturing := true
    global CaptureHadKeys := false
    global CaptureMouseKeys := Map()

    ; 注册鼠标消息钩子（滚轮 + 鼠标按键按下/松开）
    OnMessage(0x020A, OnCaptureMouseWheel, 1)      ; WM_MOUSEWHEEL
    OnMessage(0x020B, OnCaptureMouseXDown, 1)       ; WM_XBUTTONDOWN
    OnMessage(0x020C, OnCaptureMouseXUp, 1)         ; WM_XBUTTONUP
    OnMessage(0x0207, OnCaptureMouseMDown, 1)       ; WM_MBUTTONDOWN
    OnMessage(0x0208, OnCaptureMouseMUp, 1)         ; WM_MBUTTONUP
    OnMessage(0x0201, OnCaptureMouseLDown, 1)       ; WM_LBUTTONDOWN
    OnMessage(0x0202, OnCaptureMouseLUp, 1)         ; WM_LBUTTONUP
    OnMessage(0x0204, OnCaptureMouseRDown, 1)       ; WM_RBUTTONDOWN
    OnMessage(0x0205, OnCaptureMouseRUp, 1)         ; WM_RBUTTONUP

    ; 启动轮询定时器
    global CaptureTimer := CapturePolling
    SetTimer(CaptureTimer, 30)
}

RemoveAllCaptureHooks() {
    ; 停止轮询定时器
    if (CaptureTimer != "") {
        SetTimer(CaptureTimer, 0)
        global CaptureTimer := ""
    }
    ; 移除所有鼠标消息钩子
    OnMessage(0x020A, OnCaptureMouseWheel, 0)
    OnMessage(0x020B, OnCaptureMouseXDown, 0)
    OnMessage(0x020C, OnCaptureMouseXUp, 0)
    OnMessage(0x0207, OnCaptureMouseMDown, 0)
    OnMessage(0x0208, OnCaptureMouseMUp, 0)
    OnMessage(0x0201, OnCaptureMouseLDown, 0)
    OnMessage(0x0202, OnCaptureMouseLUp, 0)
    OnMessage(0x0204, OnCaptureMouseRDown, 0)
    OnMessage(0x0205, OnCaptureMouseRUp, 0)
}

; ---- 轮询函数：每 30ms 检查所有键的状态 ----
CapturePolling() {
    if !IsCapturing
        return

    ; 收集当前按住的键
    currentModifiers := Map()   ; 归一化后的修饰键 prefix -> display name
    currentKeys := []           ; 非修饰键列表

    ; 轮询键盘键
    for _, keyName in ALL_KEY_NAMES {
        if GetKeyState(keyName, "P") {
            if IsModifierKey(keyName) {
                prefix := ModifierToPrefix(keyName)
                if !currentModifiers.Has(prefix)
                    currentModifiers[prefix] := ModifierToDisplayName(keyName)
            } else {
                currentKeys.Push(keyName)
            }
        }
    }

    ; 加入当前按住的鼠标键
    for btnName, _ in CaptureMouseKeys {
        currentKeys.Push(btnName)
    }

    ; 计算总按键数
    totalPressed := currentModifiers.Count + currentKeys.Length

    if (totalPressed > 0) {
        global CaptureHadKeys := true

        ; 仅在按键数量 >= 历史峰值时更新显示和 CaptureKeys（保留最大组合）
        if (totalPressed >= CaptureKeys.Length) {
            ; 构建显示文本
            displayParts := []
            for prefix in ["^", "+", "!", "#"] {
                if currentModifiers.Has(prefix)
                    displayParts.Push(currentModifiers[prefix])
            }
            for _, k in currentKeys
                displayParts.Push(VkToDisplayName(k))

            displayStr := ""
            for i, part in displayParts {
                if (i > 1)
                    displayStr .= " + "
                displayStr .= part
            }
            try CaptureDisplayText.Value := displayStr

            ; 更新 CaptureKeys
            global CaptureKeys := []
            for prefix in ["^", "+", "!", "#"] {
                if currentModifiers.Has(prefix)
                    CaptureKeys.Push(prefix)
            }
            for _, k in currentKeys
                CaptureKeys.Push(k)
        }

        ; Escape 单独按下时取消捕获
        if (currentKeys.Length = 1 && currentKeys[1] = "Escape" && currentModifiers.Count = 0) {
            CancelCapture()
            return
        }

    } else if (CaptureHadKeys) {
        ; 所有键都松开了，确认捕获
        FinishCapture()
        return
    }
}

; ---- 完成捕获：生成 ahkKey 并应用 ----
FinishCapture() {
    global IsCapturing := false
    SetTimer(StartCaptureDelayed, 0)
    RemoveAllCaptureHooks()

    if (CaptureKeys.Length = 0) {
        try CaptureGui.Destroy()
        global CaptureGui := ""
        return
    }

    ; 分离修饰键前缀和普通键
    modifiers := ""
    mainKeys := []
    for _, k in CaptureKeys {
        if (k = "^" || k = "+" || k = "!" || k = "#")
            modifiers .= k
        else
            mainKeys.Push(k)
    }

    if (CaptureTarget = "modifier") {
        ; modifier 捕获模式：取第一个非修饰键，如果没有则取修饰键本身
        if (mainKeys.Length > 0) {
            ahkKey := mainKeys[1]
        } else {
            ; 只按了修饰键，还原为键名
            ahkKey := ModifierPrefixToKeyName(modifiers)
        }
        displayKey := KeyToDisplay(ahkKey)
        ApplyCapturedKey(ahkKey, displayKey)
    } else {
        ; source / target 捕获模式
        if (mainKeys.Length > 0) {
            ahkKey := modifiers . mainKeys[1]
        } else {
            ; 只按了修饰键
            ahkKey := ModifierPrefixToKeyName(modifiers)
        }
        displayKey := KeyToDisplay(ahkKey)
        ApplyCapturedKey(ahkKey, displayKey)
    }

    try CaptureGui.Destroy()
    global CaptureGui := ""
}

; 将修饰符前缀还原为键名（当只按了修饰键时使用）
ModifierPrefixToKeyName(prefixes) {
    ; 取最后一个修饰键
    if InStr(prefixes, "#")
        return "LWin"
    if InStr(prefixes, "!")
        return "Alt"
    if InStr(prefixes, "+")
        return "Shift"
    if InStr(prefixes, "^")
        return "Ctrl"
    return ""
}

; ---- 取消捕获 ----
CancelCapture() {
    global IsCapturing := false
    SetTimer(StartCaptureDelayed, 0)  ; 取消可能还未触发的延迟定时器
    RemoveAllCaptureHooks()
    try CaptureGui.Destroy()
    global CaptureGui := ""
}

; ---- 鼠标钩子回调 ----

; 滚轮：无按住状态，直接结合当前修饰键即时确认
OnCaptureMouseWheel(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return

    delta := (wParam >> 16) & 0xFFFF
    if (delta > 0x7FFF)
        delta := delta - 0x10000
    wheelName := delta > 0 ? "WheelUp" : "WheelDown"

    ; 将滚轮加入当前按键列表，然后立即确认
    ; 先收集当前按住的修饰键
    global CaptureHadKeys := true
    global CaptureKeys := []
    modifiers := GetCurrentModifiers()
    remaining := modifiers
    while (remaining != "") {
        ch := SubStr(remaining, 1, 1)
        if (ch = "^" || ch = "+" || ch = "!" || ch = "#") {
            CaptureKeys.Push(ch)
            remaining := SubStr(remaining, 2)
        } else {
            break
        }
    }
    ; 加入鼠标按键（如果有按住的）
    for btnName, _ in CaptureMouseKeys
        CaptureKeys.Push(btnName)
    CaptureKeys.Push(wheelName)

    FinishCapture()
    return 0
}

; 鼠标按键按下/松开：加入 CaptureMouseKeys，等轮询检测松开
OnCaptureMouseXDown(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    hiWord := (wParam >> 16) & 0xFFFF
    btnName := hiWord = 1 ? "XButton1" : "XButton2"
    CaptureMouseKeys[btnName] := true
    return 0
}

OnCaptureMouseXUp(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    hiWord := (wParam >> 16) & 0xFFFF
    btnName := hiWord = 1 ? "XButton1" : "XButton2"
    if CaptureMouseKeys.Has(btnName)
        CaptureMouseKeys.Delete(btnName)
    return 0
}

OnCaptureMouseMDown(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    CaptureMouseKeys["MButton"] := true
    return 0
}

OnCaptureMouseMUp(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    if CaptureMouseKeys.Has("MButton")
        CaptureMouseKeys.Delete("MButton")
}

OnCaptureMouseLDown(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    CaptureMouseKeys["LButton"] := true
    return 0
}

OnCaptureMouseLUp(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    if CaptureMouseKeys.Has("LButton")
        CaptureMouseKeys.Delete("LButton")
}

OnCaptureMouseRDown(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    CaptureMouseKeys["RButton"] := true
    return 0
}

OnCaptureMouseRUp(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return
    if CaptureMouseKeys.Has("RButton")
        CaptureMouseKeys.Delete("RButton")
}

GetCurrentModifiers() {
    modifiers := ""
    if GetKeyState("Ctrl")
        modifiers .= "^"
    if GetKeyState("Shift")
        modifiers .= "+"
    if GetKeyState("Alt")
        modifiers .= "!"
    if GetKeyState("LWin") || GetKeyState("RWin")
        modifiers .= "#"
    return modifiers
}

ApplyCapturedKey(ahkKey, displayKey) {
    if (CaptureTarget = "modifier") {
        EditModifierEdit.Value := displayKey
        EditModifierEdit.ahkKey := ahkKey
        UpdatePassthroughState()
    } else if (CaptureTarget = "source") {
        EditSourceEdit.Value := displayKey
        EditSourceEdit.ahkKey := ahkKey
    } else if (CaptureTarget = "target") {
        EditTargetEdit.Value := displayKey
        EditTargetEdit.ahkKey := ahkKey
    }
}

; ============================================================================
; 按键格式转换
; ============================================================================

KeyToDisplay(ahkKey) {
    if (ahkKey = "")
        return ""

    display := ""
    remaining := ahkKey

    while (remaining != "") {
        ch := SubStr(remaining, 1, 1)
        if (ch = "^") {
            display .= "Ctrl+"
            remaining := SubStr(remaining, 2)
        } else if (ch = "+") {
            display .= "Shift+"
            remaining := SubStr(remaining, 2)
        } else if (ch = "!") {
            display .= "Alt+"
            remaining := SubStr(remaining, 2)
        } else if (ch = "#") {
            display .= "Win+"
            remaining := SubStr(remaining, 2)
        } else {
            break
        }
    }

    display .= remaining
    return display
}

FormatKeyName(keyName) {
    return keyName
}

KeyToSendFormat(ahkKey) {
    if (ahkKey = "")
        return ""

    result := ""
    remaining := ahkKey

    while (remaining != "") {
        ch := SubStr(remaining, 1, 1)
        if (ch = "^" || ch = "+" || ch = "!" || ch = "#") {
            result .= ch
            remaining := SubStr(remaining, 2)
        } else {
            break
        }
    }

    if (StrLen(remaining) > 1)
        result .= "{" remaining "}"
    else
        result .= remaining

    return result
}

; ============================================================================
; 进程选择器
; ============================================================================

ShowProcessPicker(targetEdit, isMultiLine := false) {
    procGui := Gui("+Owner" MainGui.Hwnd " +ToolWindow", "选择进程")
    procGui.SetFont("s9", "Microsoft YaHei UI")

    procGui.AddText("x10 y10 w80 h23 +0x200", "手动输入:")
    manualEdit := procGui.AddEdit("x90 y10 w200 h23 vManualProc")

    procGui.AddText("x10 y40 w280 h20", "或从下方列表选择（可多选）:")

    procList := GetRunningProcesses()
    lb := procGui.AddListBox("x10 y65 w280 h200 vSelectedProc +Multi", procList)

    procGui.AddButton("x60 y275 w80 h28", "确定").OnEvent("Click", OnProcessPickOK.Bind(procGui, targetEdit, lb, manualEdit, isMultiLine))
    procGui.AddButton("x160 y275 w80 h28", "取消").OnEvent("Click", (*) => procGui.Destroy())

    procGui.Show("w300 h315")
}

OnProcessPickOK(procGui, targetEdit, lb, manualEdit, isMultiLine, *) {
    manual := Trim(manualEdit.Value)
    selected := []

    ; 收集 ListBox 多选项
    ; 多选 ListBox 的 .Value 返回索引数组，用 ControlGetItems 获取所有项文本
    try {
        indices := lb.Value  ; 多选时返回 Array of indices
        if (indices is Array) {
            allItems := ControlGetItems(lb)
            for idx in indices {
                if (idx > 0 && idx <= allItems.Length)
                    selected.Push(allItems[idx])
            }
        } else if (indices > 0) {
            ; 单选情况
            selected.Push(lb.Text)
        }
    }

    if (manual != "")
        selected.InsertAt(1, manual)

    if (selected.Length > 0) {
        if (isMultiLine) {
            ; 多行模式：追加到现有内容
            existing := targetEdit.Value
            for proc in selected {
                if (existing != "" && SubStr(existing, -1) != "`n")
                    existing .= "`n"
                existing .= proc
            }
            targetEdit.Value := existing
        } else {
            ; 单行模式：用 | 连接
            result := ""
            for i, proc in selected {
                if (i > 1)
                    result .= "|"
                result .= proc
            }
            targetEdit.Value := result
        }
    }
    procGui.Destroy()
}

GetRunningProcesses() {
    processes := Map()
    excludeList := Map(
        "svchost.exe", 1, "csrss.exe", 1, "wininit.exe", 1,
        "services.exe", 1, "lsass.exe", 1, "smss.exe", 1,
        "System", 1, "Registry", 1, "fontdrvhost.exe", 1,
        "dwm.exe", 1, "conhost.exe", 1
    )

    try {
        ids := WinGetList()
        for id in ids {
            try {
                procName := WinGetProcessName(id)
                title := WinGetTitle(id)
                if (procName != "" && title != "" && !excludeList.Has(procName))
                    processes[procName] := 1
            }
        }
    }

    result := []
    for name, _ in processes
        result.Push(name)

    n := result.Length
    if (n > 1) {
        loop n - 1 {
            i := A_Index
            loop n - i {
                j := A_Index
                if (StrCompare(result[j], result[j + 1]) > 0) {
                    temp := result[j]
                    result[j] := result[j + 1]
                    result[j + 1] := temp
                }
            }
        }
    }

    return result
}

; ============================================================================
; 热键引擎
; ============================================================================

; 创建进程匹配闭包工厂函数
; 根据配置的 processMode 返回对应的 HotIf 条件函数
MakeProcessChecker(cfg) {
    mode := cfg["processMode"]
    if (mode = "include") {
        procList := cfg["processList"]
        return (*) => CheckIncludeMatch(procList)
    } else if (mode = "exclude") {
        exclList := cfg["excludeProcessList"]
        return (*) => CheckExcludeMatch(exclList)
    }
    ; global 模式不需要 HotIf 条件
    return ""
}

; include 模式：前台窗口匹配任一进程时返回 true
CheckIncludeMatch(procList) {
    for procName in procList {
        if WinActive("ahk_exe " procName)
            return true
    }
    return false
}

; exclude 模式：前台窗口不在排除列表中时返回 true
CheckExcludeMatch(exclList) {
    try {
        fgProc := WinGetProcessName("A")
        for procName in exclList {
            if (fgProc = procName)
                return false
        }
    }
    return true
}

; 卸载所有当前热键
UnregisterAllHotkeys() {
    ; 先清理状态追踪式修饰键
    CleanupPassthroughModKeys()

    ; 卸载所有已注册的热键
    for _, hk in ActiveHotkeys {
        try {
            if (hk.Has("checker") && hk["checker"] != "")
                HotIf(hk["checker"])
            else
                HotIf()

            Hotkey(hk["key"], "Off")
            if (hk.Has("keyUp"))
                Hotkey(hk["keyUp"], "Off")
        }
    }
    HotIf()
    global ActiveHotkeys := []
    global ComboFiredState := Map()
    global PassthroughModKeys := Map()
    global InterceptModKeys := Map()
    global PassthroughHandlers := Map()
    global PassthroughSourceRegistered := Map()
    global HoldTimers := Map()
    global AllProcessCheckers := []
}

; 重新加载所有已启用配置的热键
ReloadAllHotkeys() {
    UnregisterAllHotkeys()

    ; 按优先级排序：include > exclude > global
    ; 收集各类配置
    includeConfigs := []
    excludeConfigs := []
    globalConfigs := []

    for _, cfg in AllConfigs {
        if (!cfg["enabled"])
            continue
        if (cfg["mappings"].Length = 0)
            continue

        mode := cfg["processMode"]
        if (mode = "include")
            includeConfigs.Push(cfg)
        else if (mode = "exclude")
            excludeConfigs.Push(cfg)
        else
            globalConfigs.Push(cfg)
    }

    ; 按优先级注册：include 最先（最具体），global 最后
    for _, cfg in includeConfigs
        RegisterConfigHotkeys(cfg)
    for _, cfg in excludeConfigs
        RegisterConfigHotkeys(cfg)
    for _, cfg in globalConfigs
        RegisterConfigHotkeys(cfg)

    HotIf()
}

; 为单个配置注册所有热键
RegisterConfigHotkeys(cfg) {
    mappings := cfg["mappings"]
    if (mappings.Length = 0)
        return

    ; 创建该配置的进程匹配闭包
    checker := MakeProcessChecker(cfg)
    ; 保持引用防止 GC
    if (checker != "")
        AllProcessCheckers.Push(checker)

    useCustomHotIf := (checker != "")

    ; 第一遍：收集状态追踪式映射，按 sourceKey 分组
    for idx, mapping in mappings {
        modKey := mapping["ModifierKey"]
        if (modKey = "" || !mapping["PassthroughMod"])
            continue

        srcKey := mapping["SourceKey"]
        ; 使用配置名+sourceKey 作为键，避免跨配置冲突
        groupKey := cfg["name"] "|" srcKey
        if !PassthroughHandlers.Has(groupKey)
            PassthroughHandlers[groupKey] := []

        PassthroughHandlers[groupKey].Push({
            modKey: modKey,
            targetKey: mapping["TargetKey"],
            holdRepeat: mapping["HoldRepeat"],
            repeatDelay: mapping["RepeatDelay"],
            repeatInterval: mapping["RepeatInterval"],
            idx: cfg["name"] "|" idx
        })
    }

    ; 第二遍：注册所有热键
    for idx, mapping in mappings {
        RegisterMapping(mapping, useCustomHotIf, checker, cfg["name"] "|" idx, cfg["name"])
    }
}

; 注册单个映射
RegisterMapping(mapping, useCustomHotIf, checker, uniqueIdx, configName) {
    modKey := mapping["ModifierKey"]
    sourceKey := mapping["SourceKey"]
    targetKey := mapping["TargetKey"]
    holdRepeat := mapping["HoldRepeat"]
    repeatDelay := mapping["RepeatDelay"]
    repeatInterval := mapping["RepeatInterval"]
    passthroughMod := mapping["PassthroughMod"]

    ; 设置 HotIf 条件
    if (useCustomHotIf)
        HotIf(checker)
    else
        HotIf()

    hkInfo := Map()
    hkInfo["checker"] := checker

    if (modKey = "") {
        ; ===== 路径 A：无修饰键 =====
        hkInfo["key"] := sourceKey

        if (holdRepeat) {
            downCb := HoldDownCallback.Bind(targetKey, repeatDelay, repeatInterval, uniqueIdx)
            upCb := HoldUpCallback.Bind(uniqueIdx)
            try {
                Hotkey(sourceKey, downCb, "On")
                Hotkey(sourceKey " Up", upCb, "On")
                hkInfo["keyUp"] := sourceKey " Up"
            }
        } else {
            sendCb := SendKeyCallback.Bind(targetKey)
            try Hotkey(sourceKey, sendCb, "On")
        }

    } else if (!passthroughMod) {
        ; ===== 路径 B：拦截式组合热键 =====
        comboKey := modKey " & " sourceKey
        hkInfo["key"] := comboKey

        if (holdRepeat) {
            downCb := HoldDownCallback.Bind(targetKey, repeatDelay, repeatInterval, uniqueIdx)
            upCb := HoldUpCallback.Bind(uniqueIdx)
            try {
                Hotkey(comboKey, downCb, "On")
                Hotkey(comboKey " Up", upCb, "On")
                hkInfo["keyUp"] := comboKey " Up"
            }
        } else {
            sendCb := SendKeyCallback.Bind(targetKey)
            try Hotkey(comboKey, sendCb, "On")
        }

        ; 注册修饰键恢复（同一 HotIf 条件下只注册一次）
        modRegKey := (checker != "" ? configName : "") "|" modKey
        if !InterceptModKeys.Has(modRegKey) {
            try {
                restoreCb := RestoreModKeyCallback.Bind(modKey)
                Hotkey(modKey, restoreCb, "On")
                modHkInfo := Map()
                modHkInfo["key"] := modKey
                modHkInfo["checker"] := checker
                ActiveHotkeys.Push(modHkInfo)
                InterceptModKeys[modRegKey] := true
            }
        }

    } else {
        ; ===== 路径 C：状态追踪式 =====
        groupKey := configName "|" sourceKey
        srcRegKey := (checker != "" ? configName : "") "|" sourceKey
        if !PassthroughSourceRegistered.Has(srcRegKey) {
            hkInfo["key"] := sourceKey

            handler := PassthroughSourceHandler.Bind(groupKey)
            try Hotkey(sourceKey, handler, "On")

            PassthroughSourceRegistered[srcRegKey] := true
        } else {
            hkInfo["key"] := sourceKey
        }

        ; 注册修饰键状态追踪（同一 HotIf 条件下只注册一次）
        modRegKey := (checker != "" ? configName : "") "|" modKey
        if !PassthroughModKeys.Has(modRegKey) {
            SetupPassthroughModKey(modKey, checker)
            PassthroughModKeys[modRegKey] := true
        }
    }

    ActiveHotkeys.Push(hkInfo)
}

; 设置状态追踪式修饰键的按下/松开监控
SetupPassthroughModKey(modKey, checker := "") {
    ComboFiredState[modKey] := false

    downCb := PassthroughModDown.Bind(modKey)
    upCb := PassthroughModUp.Bind(modKey)
    try {
        Hotkey("~" modKey, downCb, "On")
        Hotkey("~" modKey " Up", upCb, "On")
    }

    ; 记录用于卸载
    modHkInfo := Map()
    modHkInfo["key"] := "~" modKey
    modHkInfo["keyUp"] := "~" modKey " Up"
    modHkInfo["checker"] := checker
    ActiveHotkeys.Push(modHkInfo)
}

; 清理状态追踪式修饰键的监控
CleanupPassthroughModKeys() {
    ; 通过 ActiveHotkeys 中记录的 checker 来正确卸载
    ; （在 UnregisterAllHotkeys 的主循环中统一处理）
    ; 这里只重置状态
    global PassthroughModKeys := Map()
}

; 修饰键按下：初始化组合触发状态
PassthroughModDown(modKey, *) {
    ComboFiredState[modKey] := false
}

; 修饰键松开：如果触发过组合，尝试抑制副作用
PassthroughModUp(modKey, *) {
    if (ComboFiredState.Has(modKey) && ComboFiredState[modKey]) {
        ComboFiredState[modKey] := false
        ; ~ 前缀已经让物理事件通过，无法阻止
        ; 对于 RButton，松开可能触发右键菜单，用 Escape 关闭
        if (modKey = "RButton")
            SetTimer(DismissContextMenu, -10)
        return
    }
    ComboFiredState[modKey] := false
}

; 延迟关闭右键菜单（给系统一点时间弹出菜单后再关闭）
DismissContextMenu(*) {
    Send("{Escape}")
}

; ===== 路径 A/B 回调 =====

SendKeyCallback(targetKey, *) {
    Send(KeyToSendFormat(targetKey))
}

HoldDownCallback(targetKey, repeatDelay, repeatInterval, idx, *) {
    sendKey := KeyToSendFormat(targetKey)
    Send(sendKey)

    timerFn := RepeatTimerCallback.Bind(sendKey)
    HoldTimers[idx] := { fn: timerFn, interval: repeatInterval, active: true }
    SetTimer(StartRepeat.Bind(idx, timerFn, repeatInterval), -repeatDelay)
}

StartRepeat(idx, timerFn, interval, *) {
    if (HoldTimers.Has(idx) && HoldTimers[idx].active)
        SetTimer(timerFn, interval)
}

RepeatTimerCallback(sendKey, *) {
    Send(sendKey)
}

HoldUpCallback(idx, *) {
    if HoldTimers.Has(idx) {
        if (HoldTimers[idx].HasProp("fn"))
            SetTimer(HoldTimers[idx].fn, 0)
        HoldTimers[idx].active := false
        HoldTimers.Delete(idx)
    }
}

RestoreModKeyCallback(modKey, *) {
    Send(KeyToSendFormat(modKey))
}

; ===== 路径 C 回调（状态追踪式）=====

; sourceKey 的统一处理器：检查所有关联的修饰键
; groupKey 格式为 "configName|sourceKey"
PassthroughSourceHandler(groupKey, *) {
    if !PassthroughHandlers.Has(groupKey) {
        ; 没有关联的组合映射，从 groupKey 提取 sourceKey 转发
        parts := StrSplit(groupKey, "|",, 2)
        sourceKey := parts.Length >= 2 ? parts[2] : groupKey
        Send(KeyToSendFormat(sourceKey))
        return
    }

    handlers := PassthroughHandlers[groupKey]
    for _, h in handlers {
        if GetKeyState(h.modKey, "P") {
            ; 修饰键按住，触发组合
            ComboFiredState[h.modKey] := true

            if (h.holdRepeat) {
                ; 长按连续触发
                sendKey := KeyToSendFormat(h.targetKey)
                Send(sendKey)
                timerFn := RepeatTimerCallback.Bind(sendKey)
                HoldTimers[h.idx] := { fn: timerFn, interval: h.repeatInterval, active: true }
                SetTimer(StartRepeat.Bind(h.idx, timerFn, h.repeatInterval), -h.repeatDelay)
            } else {
                Send(KeyToSendFormat(h.targetKey))
            }
            return
        }
    }

    ; 没有任何修饰键按住，从 groupKey 提取 sourceKey 转发
    parts := StrSplit(groupKey, "|",, 2)
    sourceKey := parts.Length >= 2 ? parts[2] : groupKey
    Send(KeyToSendFormat(sourceKey))
}


; ============================================================================
; 托盘和窗口事件
; ============================================================================

OnMainClose(thisGui) {
    thisGui.Hide()
}

OnTrayShow(*) {
    MainGui.Show()
}

OnTrayExit(*) {
    UnregisterAllHotkeys()
    ExitApp()
}

OnRunAsAdmin(*) {
    if A_IsAdmin {
        MsgBox("当前已经是管理员模式", APP_NAME, "Icon!")
        return
    }
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
        ExitApp()
    } catch as e {
        MsgBox("提权失败，可能被用户取消了`n" e.Message, APP_NAME, "Icon!")
    }
}
