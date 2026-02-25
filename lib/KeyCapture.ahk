; ============================================================================
; AHKeyMap - 按键捕获模块
; 负责"松开时确认"机制的按键捕获功能
; ============================================================================

; 声明跨文件使用的全局变量
global IsCapturing
global CaptureTarget
global CaptureGui
global CaptureDisplayText
global CaptureTimer
global CaptureKeys
global CaptureHadKeys
global CaptureMouseKeys

; 编辑弹窗控件引用（从 MappingEditor 模块传入）
global EditModifierEdit
global EditSourceEdit
global EditTargetEdit
global EditPassthroughCB

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

; 这个函数需要从 MappingEditor 模块调用
UpdatePassthroughState() {
    ; 保留修饰键原始功能 仅在修饰键非空时可用
    hasModifier := EditModifierEdit.ahkKey != ""
    EditPassthroughCB.Enabled := hasModifier
    if !hasModifier
        EditPassthroughCB.Value := 0
}
