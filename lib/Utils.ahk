; ============================================================================
; AHKeyMap - Utility functions module
; Contains key format conversion, process picker, and auto-start helpers
; ============================================================================

; Declare globals shared across modules
global APP_NAME
global REG_RUN_KEY
global REG_VALUE_NAME
global ProcessPickerOpen
global ProcessPickerGui

; ============================================================================
; Key format conversion
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

; Reserved for future key display formatting tweaks (e.g. normalization)
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
; Process picker
; ============================================================================

CloseProcessPicker(procGui, *) {
    global ProcessPickerOpen := false
    global ProcessPickerGui := ""
    procGui.Destroy()
}

ShowProcessPicker(targetEdit, isMultiLine := false) {
    if (ProcessPickerOpen)
        return
    global ProcessPickerOpen := true

    procGui := Gui("+AlwaysOnTop +ToolWindow", L("Utils.ProcessPicker.Title"))
    procGui.SetFont("s9", "Microsoft YaHei UI")
    procGui.OnEvent("Close", CloseProcessPicker.Bind(procGui))

    procGui.AddText("x10 y10 w80 h23 +0x200", L("Utils.ProcessPicker.ManualLabel"))
    manualEdit := procGui.AddEdit("x90 y10 w200 h23 vManualProc")

    procGui.AddText("x10 y40 w280 h20", L("Utils.ProcessPicker.ListHint"))

    procList := GetRunningProcesses()
    lb := procGui.AddListBox("x10 y65 w280 h200 vSelectedProc +Multi", procList)

    procGui.AddButton("x60 y275 w80 h28", L("GuiEvents.Common.OkButton")).OnEvent("Click", OnProcessPickOK.Bind(procGui, targetEdit, lb, manualEdit, isMultiLine))
    procGui.AddButton("x160 y275 w80 h28", L("GuiEvents.Common.CancelButton")).OnEvent("Click", CloseProcessPicker.Bind(procGui))

    global ProcessPickerGui := procGui

    procGui.Show("w300 h315")
}

OnProcessPickOK(procGui, targetEdit, lb, manualEdit, isMultiLine, *) {
    global ProcessPickerOpen := false
    manual := Trim(manualEdit.Value)
    selected := []

    ; Collect ListBox multi-selection values
    try {
        indices := lb.Value  ; returns Array of indices when multi-select is enabled
        if (indices is Array) {
            allItems := ControlGetItems(lb)
            for idx in indices {
                if (idx > 0 && idx <= allItems.Length)
                    selected.Push(allItems[idx])
            }
        } else if (indices > 0) {
            ; Single selection case
            selected.Push(lb.Text)
        }
    }

    if (manual != "")
        selected.InsertAt(1, manual)

    if (selected.Length > 0) {
        if (isMultiLine) {
            existing := targetEdit.Value
            ; Build a set of existing process names for de-duplication
            existingSet := Map()
            loop parse existing, "`n", "`r" {
                t := Trim(A_LoopField)
                if (t != "")
                    existingSet[t] := true
            }
            for proc in selected {
                if existingSet.Has(proc)
                    continue
                if (existing != "" && SubStr(existing, -1) != "`n")
                    existing .= "`n"
                existing .= proc
                existingSet[proc] := true
            }
            targetEdit.Value := existing
        } else {
            ; Single-line mode: join with |
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

    ; Collect process names into newline-separated string and sort with built-in Sort()
    nameStr := ""
    for name, _ in processes
        nameStr .= name "`n"
    nameStr := RTrim(nameStr, "`n")
    if (nameStr = "")
        return []

    sorted := Sort(nameStr)
    result := []
    loop parse sorted, "`n" {
        if (A_LoopField != "")
            result.Push(A_LoopField)
    }
    return result
}

; ============================================================================
; Auto-start via registry
; ============================================================================

IsAutoStartEnabled() {
    try {
        val := RegRead(REG_RUN_KEY, REG_VALUE_NAME)
        return val != ""
    } catch
        return false
}

EnableAutoStart() {
    exePath := A_IsCompiled ? ('"' A_ScriptFullPath '"') : ('"' A_AhkPath '" "' A_ScriptFullPath '"')
    RegWrite(exePath, "REG_SZ", REG_RUN_KEY, REG_VALUE_NAME)
}

DisableAutoStart() {
    try RegDelete(REG_RUN_KEY, REG_VALUE_NAME)
}
