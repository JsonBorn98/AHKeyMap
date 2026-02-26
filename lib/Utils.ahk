; ============================================================================
; AHKeyMap - 工具函数模块
; 包含按键格式转换、进程选择器、开机自启等功能
; ============================================================================

; 声明跨文件使用的全局变量
global APP_NAME
global REG_RUN_KEY
global REG_VALUE_NAME
global ProcessPickerOpen

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

CloseProcessPicker(procGui, *) {
    global ProcessPickerOpen := false
    procGui.Destroy()
}

ShowProcessPicker(targetEdit, isMultiLine := false) {
    if (ProcessPickerOpen)
        return
    global ProcessPickerOpen := true

    procGui := Gui("+AlwaysOnTop +ToolWindow", "选择进程")
    procGui.SetFont("s9", "Microsoft YaHei UI")
    procGui.OnEvent("Close", CloseProcessPicker.Bind(procGui))

    procGui.AddText("x10 y10 w80 h23 +0x200", "手动输入:")
    manualEdit := procGui.AddEdit("x90 y10 w200 h23 vManualProc")

    procGui.AddText("x10 y40 w280 h20", "或从下方列表选择（可多选）:")

    procList := GetRunningProcesses()
    lb := procGui.AddListBox("x10 y65 w280 h200 vSelectedProc +Multi", procList)

    procGui.AddButton("x60 y275 w80 h28", "确定").OnEvent("Click", OnProcessPickOK.Bind(procGui, targetEdit, lb, manualEdit, isMultiLine))
    procGui.AddButton("x160 y275 w80 h28", "取消").OnEvent("Click", CloseProcessPicker.Bind(procGui))

    procGui.Show("w300 h315")
}

OnProcessPickOK(procGui, targetEdit, lb, manualEdit, isMultiLine, *) {
    global ProcessPickerOpen := false
    manual := Trim(manualEdit.Value)
    selected := []

    ; 收集 ListBox 多选项
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
    global ProcessPickerOpen := false
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

    ; 冒泡排序
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
; 开机自启（注册表）
; ============================================================================

IsAutoStartEnabled() {
    try {
        val := RegRead(REG_RUN_KEY, REG_VALUE_NAME)
        return val != ""
    } catch
        return false
}

EnableAutoStart() {
    exePath := A_IsCompiled ? A_ScriptFullPath : (A_AhkPath ' "' A_ScriptFullPath '"')
    RegWrite(exePath, "REG_SZ", REG_RUN_KEY, REG_VALUE_NAME)
}

DisableAutoStart() {
    try RegDelete(REG_RUN_KEY, REG_VALUE_NAME)
}
