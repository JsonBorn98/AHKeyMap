#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("Mapping.Make applies defaults, coercion, and clamping", Test_MappingMake_AppliesDefaultsCoercionAndClamping)
RegisterTest("Mapping.Normalize whitelists keys and fills defaults in place", Test_MappingNormalize_WhitelistsKeysAndFillsDefaults)
RegisterTest("Mapping.Normalize clamps sub-minimum repeat timing", Test_MappingNormalize_ClampsSubMinimumRepeatTiming)
RegisterTest("Mapping.Normalize coerces string flags and numeric fields", Test_MappingNormalize_CoercesStringFlagsAndNumericFields)
RegisterTest("Mapping.ClassifyPath truth table covers all three paths", Test_ClassifyPath_CoversAllThreePaths)
RegisterTest("Mapping.HotkeyStringFor derives per-path hotkey strings", Test_HotkeyStringFor_DerivesPerPathStrings)
RegisterTest("Mapping.ToIniPairs lists exactly the seven schema fields", Test_ToIniPairs_ListsExactlySevenFields)
RegisterTest("Mapping.ToIniPairs round-trips through LoadConfigData", Test_ToIniPairs_RoundTripsThroughLoadConfigData)
RegisterTest("LoadConfigData clamps hand-edited sub-minimum timing at load", Test_LoadConfigData_ClampsHandEditedTimingAtLoad)
RegisterTest("ConfigRecord.Make owns record shape, derived lists, and file path", Test_ConfigRecordMake_OwnsShapeListsAndFilePath)
RegisterTest("ConfigStore re-normalizes mappings at the store boundary", Test_ConfigStore_RenormalizesAtBoundary)

RunRegisteredTests()

Test_MappingMake_AppliesDefaultsCoercionAndClamping() {
    ; All defaults: empty timing falls back to DEFAULT_REPEAT_*
    m := Mapping.Make("", "F13", "^c")
    AssertEq(0, m["HoldRepeat"])
    AssertEq(DEFAULT_REPEAT_DELAY, m["RepeatDelay"])
    AssertEq(DEFAULT_REPEAT_INTERVAL, m["RepeatInterval"])
    AssertEq(0, m["PassthroughMod"])

    ; Explicit values are Integer()-coerced and preserved
    m := Mapping.Make("RAlt", "F13", "^c", 1, 120, 40, 1)
    AssertEq(1, m["HoldRepeat"])
    AssertEq(120, m["RepeatDelay"])
    AssertEq(40, m["RepeatInterval"])
    AssertEq(1, m["PassthroughMod"])

    ; String inputs from INI readers are coerced too
    m := Mapping.Make("", "F13", "^c", "1", "250", "30", "0")
    AssertEq(1, m["HoldRepeat"])
    AssertEq(250, m["RepeatDelay"])
    AssertEq(30, m["RepeatInterval"])
    AssertEq(0, m["PassthroughMod"])

    ; Sub-minimum timing is clamped to the schema minimum
    m := Mapping.Make("", "F13", "^c", 1, 1, 5)
    AssertEq(Mapping.MIN_REPEAT_TIMING, m["RepeatDelay"])
    AssertEq(Mapping.MIN_REPEAT_TIMING, m["RepeatInterval"])
}

Test_MappingNormalize_WhitelistsKeysAndFillsDefaults() {
    m := Map()
    m["SourceKey"] := "F13"
    m["ExtraKey"] := "stray"
    m["AnotherExtra"] := 123

    Mapping.Normalize(m)

    ; Extra keys are dropped, missing keys are filled with defaults
    AssertFalse(m.Has("ExtraKey"), "ExtraKey should be dropped by the whitelist.")
    AssertFalse(m.Has("AnotherExtra"), "AnotherExtra should be dropped by the whitelist.")
    AssertEq(7, m.Count)
    AssertEq("", m["ModifierKey"])
    AssertEq("F13", m["SourceKey"])
    AssertEq("", m["TargetKey"])
    AssertEq(0, m["HoldRepeat"])
    AssertEq(DEFAULT_REPEAT_DELAY, m["RepeatDelay"])
    AssertEq(DEFAULT_REPEAT_INTERVAL, m["RepeatInterval"])
    AssertEq(0, m["PassthroughMod"])
}

Test_MappingNormalize_ClampsSubMinimumRepeatTiming() {
    m := Map()
    m["ModifierKey"] := ""
    m["SourceKey"] := "F13"
    m["TargetKey"] := "^c"
    m["HoldRepeat"] := 1
    m["RepeatDelay"] := 5
    m["RepeatInterval"] := 9
    m["PassthroughMod"] := 0

    Mapping.Normalize(m)

    AssertEq(10, m["RepeatDelay"])
    AssertEq(10, m["RepeatInterval"])
}

Test_MappingNormalize_CoercesStringFlagsAndNumericFields() {
    m := Map()
    m["ModifierKey"] := "CapsLock"
    m["SourceKey"] := "F13"
    m["TargetKey"] := "^c"
    m["HoldRepeat"] := "1"
    m["RepeatDelay"] := "100"
    m["RepeatInterval"] := "20"
    m["PassthroughMod"] := "1"

    Mapping.Normalize(m)

    AssertEq(1, m["HoldRepeat"])
    AssertEq(100, m["RepeatDelay"])
    AssertEq(20, m["RepeatInterval"])
    AssertEq(1, m["PassthroughMod"])
}

Test_ClassifyPath_CoversAllThreePaths() {
    ; No modifier -> Path A regardless of other fields
    AssertEq(Mapping.PATH_A, Mapping.ClassifyPath(Mapping.Make("", "F13", "^c", 1, 120, 40)))
    AssertEq("A", Mapping.PATH_A)

    ; Modifier with PassthroughMod=0 -> Path B
    AssertEq(Mapping.PATH_B, Mapping.ClassifyPath(Mapping.Make("CapsLock", "F13", "^c", 1, 120, 40, 0)))
    AssertEq("B", Mapping.PATH_B)

    ; Modifier with PassthroughMod=1 -> Path C
    AssertEq(Mapping.PATH_C, Mapping.ClassifyPath(Mapping.Make("RButton", "WheelUp", "^Tab", 0, 300, 50, 1)))
    AssertEq("C", Mapping.PATH_C)

    ; Modifier with default PassthroughMod (0) -> Path B
    AssertEq(Mapping.PATH_B, Mapping.ClassifyPath(Mapping.Make("RAlt", "F14", "^v")))
}

Test_HotkeyStringFor_DerivesPerPathStrings() {
    ; Path A: the bare source key
    AssertEq("F13", Mapping.HotkeyStringFor(Mapping.Make("", "F13", "^c")))

    ; Path B: intercept combo "mod & source"
    AssertEq("CapsLock & F13", Mapping.HotkeyStringFor(Mapping.Make("CapsLock", "F13", "^c")))

    ; Path C: passthrough combo "~mod+source"
    AssertEq("~RButton+WheelUp", Mapping.HotkeyStringFor(Mapping.Make("RButton", "WheelUp", "^Tab", 0, 300, 50, 1)))
}

Test_ToIniPairs_ListsExactlySevenFields() {
    pairs := Mapping.ToIniPairs(Mapping.Make("RAlt", "F13", "^c", 1, 120, 40, 1))

    AssertEq(7, pairs.Count)
    AssertEq("RAlt", pairs["ModifierKey"])
    AssertEq("F13", pairs["SourceKey"])
    AssertEq("^c", pairs["TargetKey"])
    AssertEq("1", pairs["HoldRepeat"])
    AssertEq("120", pairs["RepeatDelay"])
    AssertEq("40", pairs["RepeatInterval"])
    AssertEq("1", pairs["PassthroughMod"])
}

Test_ToIniPairs_RoundTripsThroughLoadConfigData() {
    mappings := [
        Mapping.Make("", "F13", "^c"),
        Mapping.Make("CapsLock", "F14", "^v", 0, 300, 50, 0),
        Mapping.Make("RAlt", "F16", "^d", 1, 200, 40, 1)
    ]

    ; Seed the INI file through the same field list SaveConfig uses
    configFile := CONFIG_DIR "\RoundTrip.ini"
    IniWrite("RoundTrip", configFile, "Meta", "Name")
    IniWrite("global", configFile, "Meta", "ProcessMode")
    IniWrite("", configFile, "Meta", "Process")
    IniWrite("", configFile, "Meta", "ExcludeProcess")
    for idx, m in mappings {
        pairs := ""
        for iniKey, iniVal in Mapping.ToIniPairs(m) {
            if (pairs != "")
                pairs .= "`n"
            pairs .= iniKey "=" iniVal
        }
        IniWrite(pairs, configFile, "Mapping" idx)
    }

    loaded := LoadConfigData("RoundTrip")

    AssertEq(3, loaded["mappings"].Length)
    AssertEq("F13", loaded["mappings"][1]["SourceKey"])
    AssertEq("", loaded["mappings"][1]["ModifierKey"])
    AssertEq(0, loaded["mappings"][1]["HoldRepeat"])
    AssertEq("CapsLock", loaded["mappings"][2]["ModifierKey"])
    AssertEq("RAlt", loaded["mappings"][3]["ModifierKey"])
    AssertEq(1, loaded["mappings"][3]["HoldRepeat"])
    AssertEq(200, loaded["mappings"][3]["RepeatDelay"])
    AssertEq(40, loaded["mappings"][3]["RepeatInterval"])
    AssertEq(1, loaded["mappings"][3]["PassthroughMod"])
}

Test_LoadConfigData_ClampsHandEditedTimingAtLoad() {
    ; Hand-edited INI with sub-minimum timing: the load path now clamps it
    SeedConfigFile("HandEdited", "global", "", "", [MakeMapping("RAlt", "F13", "^c", 1, 5, 8, 1)])

    loaded := LoadConfigData("HandEdited")

    AssertEq(1, loaded["mappings"].Length)
    AssertEq(10, loaded["mappings"][1]["RepeatDelay"])
    AssertEq(10, loaded["mappings"][1]["RepeatInterval"])
}

Test_ConfigRecordMake_OwnsShapeListsAndFilePath() {
    cfg := ConfigRecord.Make("MyCfg", "include", "Code.exe|notepad.exe", "chrome.exe", false, [])

    AssertEq(CONFIG_DIR "\MyCfg.ini", cfg["file"])
    AssertEq("MyCfg", cfg["name"])
    AssertEq("include", cfg["processMode"])
    AssertEq("Code.exe|notepad.exe", cfg["process"])
    AssertEq(2, cfg["processList"].Length)
    AssertEq("notepad.exe", cfg["processList"][2])
    AssertEq("chrome.exe", cfg["excludeProcess"])
    AssertEq(1, cfg["excludeProcessList"].Length)
    AssertFalse(cfg["enabled"])
    AssertEq(0, cfg["mappings"].Length)
}

Test_ConfigStore_RenormalizesAtBoundary() {
    store := ConfigStore.Instance

    SeedConfigFile("Boundary", "global", "", "", [], 1)
    LoadAllConfigs()
    store.Select("Boundary")

    ; A mapping that violates the invariants (extra key, sub-minimum timing)
    m := Map()
    m["ModifierKey"] := "RAlt"
    m["SourceKey"] := "F13"
    m["TargetKey"] := "^c"
    m["HoldRepeat"] := "1"
    m["RepeatDelay"] := 5
    m["RepeatInterval"] := 20
    m["PassthroughMod"] := "0"
    m["ExtraKey"] := "stray"

    store.AddMapping(m)

    stored := store.SelectedMappings()[1]
    AssertFalse(stored.Has("ExtraKey"), "Extra keys should be dropped at the store boundary.")
    AssertEq(1, stored["HoldRepeat"])
    AssertEq(10, stored["RepeatDelay"])
    AssertEq(20, stored["RepeatInterval"])

    ; The persisted file carries the normalized values
    AssertEq("10", ReadConfigValue("Boundary", "Mapping1", "RepeatDelay"))
}
