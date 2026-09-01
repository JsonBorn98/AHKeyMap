#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("Store chokepoint persists atomically and round-trips mappings", Test_StoreChokepoint_PersistsAtomicallyAndRoundTrips)
RegisterTest("SaveEnabledStates preserves LastConfig and UILanguage", Test_SaveEnabledStates_PreservesStateMetadata)
RegisterTest("LoadAllConfigs reuses the existing AllConfigs array", Test_LoadAllConfigs_ReusesExistingArrayObject)
RegisterTest("Store SetScope writes Meta only for empty global config", Test_StoreSetScope_Global_WritesMetaOnly)
RegisterTest("Store AddMapping preserves order across many mappings", Test_StoreAddMapping_ManyMappings_PreservesOrder)
RegisterTest("LoadConfigData returns empty for nonexistent file", Test_LoadConfigData_NonexistentFile_ReturnsEmpty)

RunRegisteredTests()

Test_StoreChokepoint_PersistsAtomicallyAndRoundTrips() {
    store := ConfigStore.Instance
    roundTripMappings := [MakeMapping("CapsLock", "F13", "^c", 1, 120, 40, 0)]

    SeedConfigFile("RoundTrip", "global", "", "", [], 1)
    LoadAllConfigs()
    store.Select("RoundTrip")

    store.SetScope("include", "notepad.exe|Code.exe")
    store.AddMapping(roundTripMappings[1])

    configFile := CONFIG_DIR "\RoundTrip.ini"
    AssertFileExists(configFile)
    AssertFalse(FileExist(configFile ".tmp"), "Config temp file should be cleaned up after save.")

    loaded := LoadConfigData("RoundTrip")
    AssertEq("include", loaded["processMode"])
    AssertEq("notepad.exe", loaded["processList"][1])
    AssertEq("Code.exe", loaded["processList"][2])
    AssertEq(1, loaded["mappings"].Length)
    AssertEq("CapsLock", loaded["mappings"][1]["ModifierKey"])
    AssertEq("^c", loaded["mappings"][1]["TargetKey"])
    AssertEq(120, loaded["mappings"][1]["RepeatDelay"])
    AssertTrue(loaded["enabled"])

    ; The store selection points at the live record inside AllConfigs
    AssertEq("RoundTrip", store.SelectedName)
    AssertEq("RoundTrip", store.Selected()["name"])
    AssertEq(1, store.SelectedMappings().Length)
}

Test_SaveEnabledStates_PreservesStateMetadata() {
    global CurrentLangCode

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

Test_StoreSetScope_Global_WritesMetaOnly() {
    store := ConfigStore.Instance

    SeedConfigFile("EmptyCfg", "global", "", "", [], 1)
    LoadAllConfigs()
    store.Select("EmptyCfg")

    store.SetScope("global", "")

    AssertFileExists(CONFIG_DIR "\EmptyCfg.ini")

    loaded := LoadConfigData("EmptyCfg")
    AssertEq("global", loaded["processMode"])
    AssertEq(0, loaded["mappings"].Length)
}

Test_StoreAddMapping_ManyMappings_PreservesOrder() {
    store := ConfigStore.Instance

    SeedConfigFile("ManyCfg", "global", "", "", [], 1)
    LoadAllConfigs()
    store.Select("ManyCfg")

    manyMappings := [
        MakeMapping("", "F13", "^a"),
        MakeMapping("", "F14", "^b"),
        MakeMapping("CapsLock", "F15", "^c", 0, 300, 50, 0),
        MakeMapping("RAlt", "F16", "^d", 1, 200, 40, 1),
        MakeMapping("", "F17", "^e")
    ]
    for _, m in manyMappings
        store.AddMapping(m)

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
