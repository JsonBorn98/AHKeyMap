#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("ParseProcessList trims and ignores empty entries", Test_ParseProcessList_TrimsAndSkipsEmpty)
RegisterTest("ProcTextToStr converts multiline input to pipe list", Test_ProcTextToStr_JoinsLines)
RegisterTest("IsValidConfigName rejects reserved characters", Test_IsValidConfigName_ValidatesReservedCharacters)
RegisterTest("FormatProcessDisplay uses localized English summaries", Test_FormatProcessDisplay_UsesLocalizedSummary)
RegisterTest("ParseProcessList returns empty array for empty string", Test_ParseProcessList_EmptyString)
RegisterTest("ParseProcessList returns single-element array for one entry", Test_ParseProcessList_SingleEntry)
RegisterTest("IsValidConfigName accepts Unicode names", Test_IsValidConfigName_AcceptsUnicodeNames)
RegisterTest("GetConfigList skips _state.ini", Test_GetConfigList_SkipsStateFile)

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
    AssertFalse(IsValidConfigName("bad`"name"))
}

Test_FormatProcessDisplay_UsesLocalizedSummary() {
    AssertEq("Scope: Global", FormatProcessDisplay("global", [], []))
    AssertEq("Scope: Only notepad.exe", FormatProcessDisplay("include", ["notepad.exe"], []))
    AssertEq("Scope: Exclude notepad.exe and 2 more", FormatProcessDisplay("exclude", [], ["notepad.exe", "code.exe", "devenv.exe"]))
}

Test_ParseProcessList_EmptyString() {
    result := ParseProcessList("")
    AssertEq(0, result.Length)
}

Test_ParseProcessList_SingleEntry() {
    result := ParseProcessList("notepad.exe")
    AssertEq(1, result.Length)
    AssertEq("notepad.exe", result[1])
}

Test_IsValidConfigName_AcceptsUnicodeNames() {
    AssertTrue(IsValidConfigName("日本語設定"))
    AssertTrue(IsValidConfigName("Profil für Arbeit"))
    AssertTrue(IsValidConfigName("游戏配置"))
}

Test_GetConfigList_SkipsStateFile() {
    ; Seed _state.ini and one real config file
    IniWrite("TestConfig", STATE_FILE, "State", "LastConfig")
    SeedConfigFile("Foo")

    configs := GetConfigList()
    AssertEq(1, configs.Length)
    AssertEq("Foo", configs[1])
}
