#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

RegisterTest("BuildKeyNameList contains expected keyboard keys", Test_BuildKeyNameList_ContainsExpectedKeys)
RegisterTest("BuildKeyNameList excludes mouse buttons and wheel", Test_BuildKeyNameList_ExcludesMouseButtons)
RegisterTest("VkToDisplayName maps known VK codes to readable symbols", Test_VkToDisplayName_MapsKnownCodes)
RegisterTest("VkToDisplayName passes through unknown key names", Test_VkToDisplayName_PassesThroughUnknown)
RegisterTest("IsModifierKey detects all 8 modifier keys and rejects non-modifiers", Test_IsModifierKey_DetectsAllModifiers)
RegisterTest("ModifierToPrefix returns correct AHK prefix symbols", Test_ModifierToPrefix_ReturnsCorrectSymbols)
RegisterTest("ModifierPrefixToKeyName reverses prefix to key name", Test_ModifierPrefixToKeyName_ReversesPrefix)

RunRegisteredTests()

; ============================================================================
; Test implementations
; ============================================================================

Test_BuildKeyNameList_ContainsExpectedKeys() {
    keys := BuildKeyNameList()
    AssertTrue(keys.Length > 50, "Key list should have > 50 entries, got " keys.Length)

    ; Modifier keys
    AssertArrayContains(keys, "LCtrl")
    AssertArrayContains(keys, "RCtrl")
    AssertArrayContains(keys, "LShift")
    AssertArrayContains(keys, "RAlt")
    AssertArrayContains(keys, "LWin")

    ; Letter keys
    AssertArrayContains(keys, "A")
    AssertArrayContains(keys, "Z")

    ; Number keys
    AssertArrayContains(keys, "0")
    AssertArrayContains(keys, "9")

    ; Function keys
    AssertArrayContains(keys, "F1")
    AssertArrayContains(keys, "F12")

    ; Special keys
    AssertArrayContains(keys, "Space")
    AssertArrayContains(keys, "Enter")
    AssertArrayContains(keys, "Escape")

    ; Numpad keys
    AssertArrayContains(keys, "Numpad0")
    AssertArrayContains(keys, "NumpadEnter")

    ; VK symbol keys
    AssertArrayContains(keys, "vkBA")
    AssertArrayContains(keys, "vkC0")
}

Test_BuildKeyNameList_ExcludesMouseButtons() {
    keys := BuildKeyNameList()

    ; Mouse buttons should NOT be in the polling list (handled by mouse hooks)
    AssertArrayNotContains(keys, "LButton")
    AssertArrayNotContains(keys, "RButton")
    AssertArrayNotContains(keys, "MButton")
    AssertArrayNotContains(keys, "XButton1")
    AssertArrayNotContains(keys, "XButton2")

    ; Wheel events should NOT be in the polling list
    AssertArrayNotContains(keys, "WheelUp")
    AssertArrayNotContains(keys, "WheelDown")
    AssertArrayNotContains(keys, "WheelLeft")
    AssertArrayNotContains(keys, "WheelRight")
}

Test_VkToDisplayName_MapsKnownCodes() {
    AssertEq(";", VkToDisplayName("vkBA"))
    AssertEq("=", VkToDisplayName("vkBB"))
    AssertEq(",", VkToDisplayName("vkBC"))
    AssertEq("-", VkToDisplayName("vkBD"))
    AssertEq(".", VkToDisplayName("vkBE"))
    AssertEq("/", VkToDisplayName("vkBF"))
    AssertEq("``", VkToDisplayName("vkC0"))
    AssertEq("[", VkToDisplayName("vkDB"))
    AssertEq("\", VkToDisplayName("vkDC"))
    AssertEq("]", VkToDisplayName("vkDD"))
    AssertEq("'", VkToDisplayName("vkDE"))
}

Test_VkToDisplayName_PassesThroughUnknown() {
    ; Non-VK key names pass through unchanged
    AssertEq("F13", VkToDisplayName("F13"))
    AssertEq("Space", VkToDisplayName("Space"))
    AssertEq("A", VkToDisplayName("A"))
    AssertEq("", VkToDisplayName(""))
}

Test_IsModifierKey_DetectsAllModifiers() {
    ; All 8 modifier keys should return true
    AssertTrue(IsModifierKey("LCtrl"))
    AssertTrue(IsModifierKey("RCtrl"))
    AssertTrue(IsModifierKey("LShift"))
    AssertTrue(IsModifierKey("RShift"))
    AssertTrue(IsModifierKey("LAlt"))
    AssertTrue(IsModifierKey("RAlt"))
    AssertTrue(IsModifierKey("LWin"))
    AssertTrue(IsModifierKey("RWin"))

    ; Non-modifier keys should return false
    AssertFalse(IsModifierKey("A"))
    AssertFalse(IsModifierKey("Space"))
    AssertFalse(IsModifierKey("CapsLock"))
    AssertFalse(IsModifierKey("Ctrl"))  ; bare "Ctrl" is not a valid modifier name
    AssertFalse(IsModifierKey(""))
}

Test_ModifierToPrefix_ReturnsCorrectSymbols() {
    AssertEq("^", ModifierToPrefix("LCtrl"))
    AssertEq("^", ModifierToPrefix("RCtrl"))
    AssertEq("+", ModifierToPrefix("LShift"))
    AssertEq("+", ModifierToPrefix("RShift"))
    AssertEq("!", ModifierToPrefix("LAlt"))
    AssertEq("!", ModifierToPrefix("RAlt"))
    AssertEq("#", ModifierToPrefix("LWin"))
    AssertEq("#", ModifierToPrefix("RWin"))

    ; Non-modifier keys return empty string
    AssertEq("", ModifierToPrefix("A"))
    AssertEq("", ModifierToPrefix("CapsLock"))
    AssertEq("", ModifierToPrefix(""))
}

Test_ModifierPrefixToKeyName_ReversesPrefix() {
    AssertEq("Ctrl", ModifierPrefixToKeyName("^"))
    AssertEq("Shift", ModifierPrefixToKeyName("+"))
    AssertEq("Alt", ModifierPrefixToKeyName("!"))
    AssertEq("LWin", ModifierPrefixToKeyName("#"))

    ; Empty prefix returns empty string
    AssertEq("", ModifierPrefixToKeyName(""))

    ; Combined prefixes: returns highest-priority match (# > ! > + > ^)
    AssertEq("LWin", ModifierPrefixToKeyName("^+!#"))
    AssertEq("Alt", ModifierPrefixToKeyName("^+!"))
}
