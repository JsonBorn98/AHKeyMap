#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("KeyToDisplay expands modifier prefixes", Test_KeyToDisplay_ExpandsModifiers)
RegisterTest("KeyToSendFormat wraps named keys and preserves single chars", Test_KeyToSendFormat_FormatsKeysForSend)
RegisterTest("SupportsKeyUpHotkey skips wheel inputs", Test_SupportsKeyUpHotkey_SkipsWheelInputs)
RegisterTest("Localization falls back to English pack and printable keys", Test_Localization_FallsBackToEnglishAndKeyName)
RegisterTest("RestoreModKeyCallback skips mouse modifiers and restores keyboard modifiers", Test_RestoreModKeyCallback_RespectsModifierKind)

RunRegisteredTests()

Test_KeyToDisplay_ExpandsModifiers() {
    AssertEq("Ctrl+Shift+Tab", KeyToDisplay("^+Tab"))
    AssertEq("Alt+Win+F13", KeyToDisplay("!#F13"))
}

Test_KeyToSendFormat_FormatsKeysForSend() {
    AssertEq("^c", KeyToSendFormat("^c"))
    AssertEq("^{Tab}", KeyToSendFormat("^Tab"))
    AssertEq("{CapsLock}", KeyToSendFormat("CapsLock"))
}

Test_SupportsKeyUpHotkey_SkipsWheelInputs() {
    AssertTrue(SupportsKeyUpHotkey("*F13"))
    AssertFalse(SupportsKeyUpHotkey("*WheelUp"))
    AssertFalse(SupportsKeyUpHotkey("~WheelDown"))
}

Test_Localization_FallsBackToEnglishAndKeyName() {
    CurrentLangCode := "fr-FR"
    AssertEq("Config:", L("GuiMain.ConfigLabel"))
    AssertEq("[Missing.Localization.Key]", L("Missing.Localization.Key"))
}

Test_RestoreModKeyCallback_RespectsModifierKind() {
    EnableSendCapture()
    RestoreModKeyCallback("CapsLock")
    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("{CapsLock}", CapturedSendKeys[1])

    EnableSendCapture()
    RestoreModKeyCallback("MButton")
    AssertEq(0, CapturedSendKeys.Length)
}
