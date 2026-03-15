; ============================================================================
; AHKeyMap - Key capture module
; Implements the "confirm on release" key capture behavior
; ============================================================================

; Declare globals shared across modules
global IsCapturing
global CaptureTarget
global CaptureGui
global CaptureDisplayText
global CaptureTimer
global CaptureKeys
global CaptureHadKeys
global CaptureMouseKeys
global CAPTURE_START_DELAY
global CAPTURE_POLL_INTERVAL

; Editor dialog control references (injected from MappingEditor module)
global EditModifierEdit
global EditSourceEdit
global EditTargetEdit
global EditPassthroughCB

; ============================================================================
; Key capture (confirm on release flow)
; ============================================================================

; Build the full list of key names to poll
global ALL_KEY_NAMES := BuildKeyNameList()

BuildKeyNameList() {
    keys := []
    ; Modifier keys (detect left/right separately, normalize for display)
    for k in ["LCtrl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin"]
        keys.Push(k)
    ; Letter keys
    loop 26
        keys.Push(Chr(64 + A_Index))  ; A-Z
    ; Number keys
    loop 10
        keys.Push(String(A_Index - 1))  ; 0-9
    ; Function keys (F1-F12 only; F13-F24 rarely exist and GetKeyState may misreport)
    loop 12
        keys.Push("F" A_Index)  ; F1-F12
    ; Special keys
    for k in ["Space", "Enter", "Tab", "Backspace", "Delete", "Insert",
              "Home", "End", "PgUp", "PgDn", "Up", "Down", "Left", "Right",
              "PrintScreen", "ScrollLock", "Pause", "CapsLock", "NumLock",
              "Escape", "AppsKey",
              "Numpad0", "Numpad1", "Numpad2", "Numpad3", "Numpad4",
              "Numpad5", "Numpad6", "Numpad7", "Numpad8", "Numpad9",
              "NumpadDot", "NumpadDiv", "NumpadMult", "NumpadAdd", "NumpadSub", "NumpadEnter"]
        keys.Push(k)
    ; Symbol keys (use VK names to avoid layout-specific scancode issues)
    for k in ["vkBA", "vkBB", "vkBC", "vkBD", "vkBE", "vkBF", "vkC0",
              "vkDB", "vkDC", "vkDD", "vkDE"]
        keys.Push(k)
    return keys
}

; Map VK codes to readable names
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

; Helper predicates/mappers for modifiers
IsModifierKey(keyName) {
    return (keyName = "LCtrl" || keyName = "RCtrl"
         || keyName = "LShift" || keyName = "RShift"
         || keyName = "LAlt" || keyName = "RAlt"
         || keyName = "LWin" || keyName = "RWin")
}

; Normalize modifier key names into AHK prefix symbols
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

; Normalize modifier key names into display names
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
    global IsCapturing := false  ; start disabled, enable after delay
    global CaptureKeys := []
    global CaptureHadKeys := false
    global CaptureMouseKeys := Map()

    ; Create capture hint window with live display
    global CaptureGui := Gui("+AlwaysOnTop +ToolWindow -SysMenu", L("KeyCapture.Title"))
    CaptureGui.SetFont("s11", "Microsoft YaHei UI")
    global CaptureDisplayText := CaptureGui.AddText("x20 y10 w300 h30 Center", L("KeyCapture.MainPrompt"))
    CaptureGui.SetFont("s9", "Microsoft YaHei UI")
    CaptureGui.AddText("x20 y45 w300 h20 Center cGray", L("KeyCapture.SubPrompt"))
    CaptureGui.Show("w340 h75")

    ; Delay capture start to avoid capturing the click on the "Capture" button itself
    SetTimer(StartCaptureDelayed, -CAPTURE_START_DELAY)
}

StartCaptureDelayed() {
    ; If the capture window was closed during the delay, bail out
    if (CaptureGui = "")
        return

    global IsCapturing := true
    global CaptureHadKeys := false
    global CaptureMouseKeys := Map()

    ; Register mouse message hooks (wheel + mouse button down/up)
    OnMessage(0x020A, OnCaptureMouseWheel, 1)      ; WM_MOUSEWHEEL
    OnMessage(0x020B, OnCaptureMouseXDown, 1)       ; WM_XBUTTONDOWN
    OnMessage(0x020C, OnCaptureMouseXUp, 1)         ; WM_XBUTTONUP
    OnMessage(0x0207, OnCaptureMouseMDown, 1)       ; WM_MBUTTONDOWN
    OnMessage(0x0208, OnCaptureMouseMUp, 1)         ; WM_MBUTTONUP
    OnMessage(0x0201, OnCaptureMouseLDown, 1)       ; WM_LBUTTONDOWN
    OnMessage(0x0202, OnCaptureMouseLUp, 1)         ; WM_LBUTTONUP
    OnMessage(0x0204, OnCaptureMouseRDown, 1)       ; WM_RBUTTONDOWN
    OnMessage(0x0205, OnCaptureMouseRUp, 1)         ; WM_RBUTTONUP

    ; Start polling timer
    global CaptureTimer := CapturePolling
    SetTimer(CaptureTimer, CAPTURE_POLL_INTERVAL)
}

RemoveAllCaptureHooks() {
    ; Stop polling timer
    if (CaptureTimer != "") {
        SetTimer(CaptureTimer, 0)
        global CaptureTimer := ""
    }
    ; Remove all mouse message hooks
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

; ---- Polling routine: check all key states every 30ms ----
CapturePolling() {
    if !IsCapturing
        return

    ; Auto-cancel capture when the window loses focus
    try {
        if (CaptureGui != "" && !WinActive("ahk_id " CaptureGui.Hwnd)) {
            CancelCapture()
            return
        }
    }

    ; Collect currently pressed keys
    currentModifiers := Map()   ; normalized modifier prefix -> display name
    currentKeys := []           ; non-modifier keys

    ; Poll keyboard keys
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

    ; Merge currently pressed mouse buttons
    for btnName, _ in CaptureMouseKeys {
        currentKeys.Push(btnName)
    }

    ; Compute total number of pressed keys
    totalPressed := currentModifiers.Count + currentKeys.Length

    if (totalPressed > 0) {
        global CaptureHadKeys := true

        ; Only update display and CaptureKeys when count >= historical max (keep largest combo)
        if (totalPressed >= CaptureKeys.Length) {
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

            ; Update CaptureKeys
            global CaptureKeys := []
            for prefix in ["^", "+", "!", "#"] {
                if currentModifiers.Has(prefix)
                    CaptureKeys.Push(prefix)
            }
            for _, k in currentKeys
                CaptureKeys.Push(k)
        }

        ; Cancel capture when only Escape is pressed
        if (currentKeys.Length = 1 && currentKeys[1] = "Escape" && currentModifiers.Count = 0) {
            CancelCapture()
            return
        }

    } else if (CaptureHadKeys) {
        ; All keys released after having pressed some: confirm capture
        FinishCapture()
        return
    }
}

; ---- Finalize capture: build ahkKey and apply ----
FinishCapture() {
    global IsCapturing := false
    SetTimer(StartCaptureDelayed, 0)
    RemoveAllCaptureHooks()

    if (CaptureKeys.Length = 0) {
        try CaptureGui.Destroy()
        global CaptureGui := ""
        return
    }

    ; Split modifier prefixes and non-modifier keys
    modifiers := ""
    mainKeys := []
    for _, k in CaptureKeys {
        if (k = "^" || k = "+" || k = "!" || k = "#")
            modifiers .= k
        else
            mainKeys.Push(k)
    }

    if (CaptureTarget = "modifier") {
        ; Modifier capture mode: take first non-modifier key, or the modifier itself
        if (mainKeys.Length > 0) {
            ahkKey := mainKeys[1]
        } else {
            ; Only modifiers were pressed, restore back to a key name
            ahkKey := ModifierPrefixToKeyName(modifiers)
        }
        displayKey := KeyToDisplay(ahkKey)
        ApplyCapturedKey(ahkKey, displayKey)
    } else {
        ; Source / target capture mode
        if (mainKeys.Length > 0) {
            ahkKey := modifiers . mainKeys[1]
        } else {
            ; Only modifiers were pressed
            ahkKey := ModifierPrefixToKeyName(modifiers)
        }
        displayKey := KeyToDisplay(ahkKey)
        ApplyCapturedKey(ahkKey, displayKey)
    }

    try CaptureGui.Destroy()
    global CaptureGui := ""
}

; Restore modifier prefixes back to a key name (used when only modifiers were pressed)
ModifierPrefixToKeyName(prefixes) {
    ; Use the last modifier in the sequence
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

; ---- Cancel capture ----
CancelCapture() {
    global IsCapturing := false
    SetTimer(StartCaptureDelayed, 0)  ; cancel any pending delayed timer
    RemoveAllCaptureHooks()
    try CaptureGui.Destroy()
    global CaptureGui := ""
}

; ---- Mouse hook callbacks ----

; Mouse wheel: without held state, combine with current modifiers and confirm immediately
OnCaptureMouseWheel(wParam, lParam, msg, hwnd) {
    if !IsCapturing
        return

    delta := (wParam >> 16) & 0xFFFF
    if (delta > 0x7FFF)
        delta := delta - 0x10000
    wheelName := delta > 0 ? "WheelUp" : "WheelDown"

    ; Add wheel into current key list and confirm immediately
    ; First collect currently pressed modifiers
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
    ; Add pressed mouse buttons (if any)
    for btnName, _ in CaptureMouseKeys
        CaptureKeys.Push(btnName)
    CaptureKeys.Push(wheelName)

    FinishCapture()
    return 0
}

; Mouse button down/up: update CaptureMouseKeys and let polling detect release
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
    return 0
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
    return 0
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
    return 0
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

; This function must be called from the MappingEditor module
UpdatePassthroughState() {
    ; "Keep modifier behavior" option is only meaningful when a modifier is set
    hasModifier := EditModifierEdit.ahkKey != ""
    EditPassthroughCB.Enabled := hasModifier
    if !hasModifier
        EditPassthroughCB.Value := 0
}
