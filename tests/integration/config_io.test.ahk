#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\AHKeyMap.ahk"
#Include "..\_support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("SaveConfig writes atomically and round-trips mappings", Test_SaveConfig_WritesAtomicallyAndRoundTrips)
RegisterTest("SaveEnabledStates preserves LastConfig and UILanguage", Test_SaveEnabledStates_PreservesStateMetadata)
RegisterTest("LoadAllConfigs reuses the existing AllConfigs array", Test_LoadAllConfigs_ReusesExistingArrayObject)

RunRegisteredTests()

Test_SaveConfig_WritesAtomicallyAndRoundTrips() {
    mappings := [MakeMapping("CapsLock", "F13", "^c", 1, 120, 40, 0)]

    CurrentConfigName := "RoundTrip"
    CurrentConfigFile := CONFIG_DIR "\RoundTrip.ini"
    CurrentProcessMode := "include"
    CurrentProcess := "notepad.exe|Code.exe"
    CurrentProcessList := ParseProcessList(CurrentProcess)
    CurrentExcludeProcess := ""
    CurrentExcludeProcessList := []
    CurrentConfigEnabled := true
    Mappings.Length := 0
    Mappings.Push(mappings[1])

    AllConfigs.Push(BuildConfigRecord("RoundTrip", CurrentProcessMode, CurrentProcess, "", true, mappings))

    SaveConfig()

    AssertFileExists(CurrentConfigFile)
    AssertFalse(FileExist(CurrentConfigFile ".tmp"), "Config temp file should be cleaned up after save.")

    loaded := LoadConfigData("RoundTrip")
    AssertEq("include", loaded["processMode"])
    AssertEq("notepad.exe", loaded["processList"][1])
    AssertEq("Code.exe", loaded["processList"][2])
    AssertEq(1, loaded["mappings"].Length)
    AssertEq("CapsLock", loaded["mappings"][1]["ModifierKey"])
    AssertEq("^c", loaded["mappings"][1]["TargetKey"])
    AssertEq(120, loaded["mappings"][1]["RepeatDelay"])
    AssertTrue(loaded["enabled"])
}

Test_SaveEnabledStates_PreservesStateMetadata() {
    IniWrite("SmokeConfig", STATE_FILE, "State", "LastConfig")
    CurrentLangCode := "zh-CN"

    AllConfigs.Push(BuildConfigRecord("Alpha", "global", "", "", true, []))
    AllConfigs.Push(BuildConfigRecord("Beta", "global", "", "", false, []))

    SaveEnabledStates()

    AssertFileExists(STATE_FILE)
    AssertFalse(FileExist(STATE_FILE ".tmp"), "State temp file should be cleaned up after save.")
    AssertEq("SmokeConfig", ReadStateValue("State", "LastConfig"))
    AssertEq("zh-CN", ReadStateValue("State", "UILanguage"))
    AssertEq("1", ReadStateValue("EnabledConfigs", "Alpha"))
    AssertEq("0", ReadStateValue("EnabledConfigs", "Beta"))
}

Test_LoadAllConfigs_ReusesExistingArrayObject() {
    originalPtr := ObjPtr(AllConfigs)

    SeedConfigFile("Alpha", "global", "", "", [MakeMapping("", "F13", "^c")], 1)
    SeedConfigFile("Beta", "exclude", "", "chrome.exe|code.exe", [MakeMapping("RAlt", "F14", "^v", 0, 300, 50, 1)], 0)

    LoadAllConfigs()

    AssertEq(originalPtr, ObjPtr(AllConfigs))
    AssertEq(2, AllConfigs.Length)
    AssertEq("Alpha", AllConfigs[1]["name"])
    AssertEq("Beta", AllConfigs[2]["name"])
    AssertFalse(AllConfigs[2]["enabled"])
}
