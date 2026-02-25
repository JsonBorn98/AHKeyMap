; ============================================================================
; AHKeyMap - GUI 事件处理模块
; 负责配置管理和映射管理的所有 GUI 事件处理
; ============================================================================

; 声明跨文件使用的全局变量
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
    DestroyModalGui(changeGui)
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
