#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\AHKeyMap.ahk"
#Include "..\_support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("ParseProcessList trims and ignores empty entries", Test_ParseProcessList_TrimsAndSkipsEmpty)
RegisterTest("ProcTextToStr converts multiline input to pipe list", Test_ProcTextToStr_JoinsLines)
RegisterTest("IsValidConfigName rejects reserved characters", Test_IsValidConfigName_ValidatesReservedCharacters)
RegisterTest("FormatProcessDisplay uses localized English summaries", Test_FormatProcessDisplay_UsesLocalizedSummary)

RunRegisteredTests()

Test_ParseProcessList_TrimsAndSkipsEmpty() {
    result := ParseProcessList("  notepad.exe | | chrome.exe || code.exe  ")

    AssertEq(3, result.Length)
    AssertEq("notepad.exe", result[1])
    AssertEq("chrome.exe", result[2])
    AssertEq("code.exe", result[3])
}

Test_ProcTextToStr_JoinsLines() {
    rawText := "notepad.exe`n`n  chrome.exe  `r`ncode.exe`n"
    AssertEq("notepad.exe|chrome.exe|code.exe", ProcTextToStr(rawText))
}

Test_IsValidConfigName_ValidatesReservedCharacters() {
    AssertTrue(IsValidConfigName("Work Profile"))
    AssertTrue(IsValidConfigName("Browser.Tools"))
    AssertFalse(IsValidConfigName("bad|name"))
    AssertFalse(IsValidConfigName("bad:name"))
    AssertFalse(IsValidConfigName("bad""name"))
}

Test_FormatProcessDisplay_UsesLocalizedSummary() {
    AssertEq("Scope: Global", FormatProcessDisplay("global", [], []))
    AssertEq("Scope: Only notepad.exe", FormatProcessDisplay("include", ["notepad.exe"], []))
    AssertEq("Scope: Exclude notepad.exe and 2 more", FormatProcessDisplay("exclude", [], ["notepad.exe", "code.exe", "devenv.exe"]))
}
