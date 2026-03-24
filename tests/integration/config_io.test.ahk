#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("SaveConfig writes atomically and round-trips mappings", Test_SaveConfig_WritesAtomicallyAndRoundTrips)
RegisterTest("SaveEnabledStates preserves LastConfig and UILanguage", Test_SaveEnabledStates_PreservesStateMetadata)
RegisterTest("LoadAllConfigs reuses the existing AllConfigs array", Test_LoadAllConfigs_ReusesExistingArrayObject)
RegisterTest("SaveConfig with empty mappings writes Meta only", Test_SaveConfig_EmptyMappings_WritesMetaOnly)
RegisterTest("SaveConfig with many mappings preserves order", Test_SaveConfig_ManyMappings_PreservesOrder)
RegisterTest("LoadConfigData returns empty for nonexistent file", Test_LoadConfigData_NonexistentFile_ReturnsEmpty)

RunRegisteredTests()

Test_SaveConfig_WritesAtomicallyAndRoundTrips() {
    global CurrentConfigName
    global CurrentConfigFile
    global CurrentProcessMode
    global CurrentProcess
    global CurrentProcessList
    global CurrentExcludeProcess
    global CurrentExcludeProcessList
    global CurrentConfigEnabled
    global Mappings
    global AllConfigs

    roundTripMappings := [MakeMapping("CapsLock", "F13", "^c", 1, 120, 40, 0)]

    CurrentConfigName := "RoundTrip"
    CurrentConfigFile := CONFIG_DIR "\RoundTrip.ini"
    CurrentProcessMode := "include"
    CurrentProcess := "notepad.exe|Code.exe"
    CurrentProcessList := ParseProcessList(CurrentProcess)
    CurrentExcludeProcess := ""
    CurrentExcludeProcessList := []
    CurrentConfigEnabled := true
    Mappings.Length := 0
    Mappings.Push(roundTripMappings[1])

    AllConfigs.Push(BuildConfigRecord("RoundTrip", CurrentProcessMode, CurrentProcess, "", true, roundTripMappings))

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
    global CurrentLangCode
    global AllConfigs

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
    global AllConfigs

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

Test_SaveConfig_EmptyMappings_WritesMetaOnly() {
    global CurrentConfigName
    global CurrentConfigFile
    global CurrentProcessMode
    global CurrentProcess
    global CurrentProcessList
    global CurrentExcludeProcess
    global CurrentExcludeProcessList
    global CurrentConfigEnabled
    global Mappings
    global AllConfigs

    CurrentConfigName := "EmptyCfg"
    CurrentConfigFile := CONFIG_DIR "\EmptyCfg.ini"
    CurrentProcessMode := "global"
    CurrentProcess := ""
    CurrentProcessList := []
    CurrentExcludeProcess := ""
    CurrentExcludeProcessList := []
    CurrentConfigEnabled := true
    Mappings.Length := 0

    AllConfigs.Push(BuildConfigRecord("EmptyCfg", "global", "", "", true, []))

    SaveConfig()
    AssertFileExists(CurrentConfigFile)

    loaded := LoadConfigData("EmptyCfg")
    AssertEq("global", loaded["processMode"])
    AssertEq(0, loaded["mappings"].Length)
}

Test_SaveConfig_ManyMappings_PreservesOrder() {
    global CurrentConfigName
    global CurrentConfigFile
    global CurrentProcessMode
    global CurrentProcess
    global CurrentProcessList
    global CurrentExcludeProcess
    global CurrentExcludeProcessList
    global CurrentConfigEnabled
    global Mappings
    global AllConfigs

    manyMappings := [
        MakeMapping("", "F13", "^a"),
        MakeMapping("", "F14", "^b"),
        MakeMapping("CapsLock", "F15", "^c", 0, 300, 50, 0),
        MakeMapping("RAlt", "F16", "^d", 1, 200, 40, 1),
        MakeMapping("", "F17", "^e")
    ]

    CurrentConfigName := "ManyCfg"
    CurrentConfigFile := CONFIG_DIR "\ManyCfg.ini"
    CurrentProcessMode := "include"
    CurrentProcess := "notepad.exe"
    CurrentProcessList := ParseProcessList(CurrentProcess)
    CurrentExcludeProcess := ""
    CurrentExcludeProcessList := []
    CurrentConfigEnabled := true
    Mappings.Length := 0
    for _, m in manyMappings
        Mappings.Push(m)

    AllConfigs.Push(BuildConfigRecord("ManyCfg", "include", "notepad.exe", "", true, manyMappings))

    SaveConfig()

    loaded := LoadConfigData("ManyCfg")
    AssertEq(5, loaded["mappings"].Length)
    AssertEq("F13", loaded["mappings"][1]["SourceKey"])
    AssertEq("F14", loaded["mappings"][2]["SourceKey"])
    AssertEq("F15", loaded["mappings"][3]["SourceKey"])
    AssertEq("F16", loaded["mappings"][4]["SourceKey"])
    AssertEq("F17", loaded["mappings"][5]["SourceKey"])
    ; Verify specific field preservation
    AssertEq("CapsLock", loaded["mappings"][3]["ModifierKey"])
    AssertEq(1, loaded["mappings"][4]["HoldRepeat"])
    AssertEq(200, loaded["mappings"][4]["RepeatDelay"])
}

Test_LoadConfigData_NonexistentFile_ReturnsEmpty() {
    result := LoadConfigData("NoSuchConfig")
    AssertEq("", result)
}
