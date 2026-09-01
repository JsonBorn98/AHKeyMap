#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("BuildStatusSummary reports enabled counts without warnings", Test_BuildStatusSummary_PlainCounts)
RegisterTest("BuildStatusSummary appends warning suffixes for conflicts and reg errors", Test_BuildStatusSummary_WarningSuffixes)
RegisterTest("BuildStatusSummary handles an empty reload result", Test_BuildStatusSummary_EmptyResult)
RegisterTest("BuildMappingRows formats modifier, passthrough mode, and timing columns", Test_BuildMappingRows_ColumnFormatting)
RegisterTest("BuildMappingRows leaves timing blank for non-hold mappings", Test_BuildMappingRows_BlankTimingWithoutHold)
RegisterTest("BuildMappingRows translates key names for display", Test_BuildMappingRows_KeyDisplay)
RegisterTest("BuildStatusDetails lists conflicts and registration errors", Test_BuildStatusDetails_ListsIssues)
RegisterTest("BuildStatusDetails returns empty when there is nothing to report", Test_BuildStatusDetails_Empty)
RegisterTest("FormatProcessDisplay uses localized summaries", Test_FormatProcessDisplay_LocalizedSummaries)
RegisterTest("ConfigStore notifies OnChanged with the reload result through the chokepoint", Test_ConfigStore_OnChanged_ReceivesReloadResult)
RegisterTest("ConfigStore Select notifies render-only without a reload result", Test_ConfigStore_Select_NotifiesRenderOnly)
RegisterTest("ConfigStore stays silent headless when nothing is registered", Test_ConfigStore_Headless_NoRegistrationNeeded)

RunRegisteredTests()

MakeReloadResult(conflictCount := 0, regErrorCount := 0) {
    conflicts := []
    loop conflictCount
        conflicts.Push({ hotkey: "F13", config1: "A", idx1: 1, config2: "B", idx2: 1 })
    regErrors := []
    loop regErrorCount
        regErrors.Push("BadKey" A_Index)
    return { conflicts: conflicts, regErrors: regErrors }
}

Test_BuildStatusSummary_PlainCounts() {
    configs := [
        BuildConfigRecord("A", "global", "", "", true, []),
        BuildConfigRecord("B", "global", "", "", false, []),
        BuildConfigRecord("C", "global", "", "", true, [])
    ]

    vm := BuildStatusSummary(configs, MakeReloadResult())

    AssertEq("Enabled 2/3", vm.text)
    AssertFalse(vm.hasWarning)
}

Test_BuildStatusSummary_WarningSuffixes() {
    configs := [BuildConfigRecord("A", "global", "", "", true, [])]

    vm := BuildStatusSummary(configs, MakeReloadResult(2, 1))

    AssertEq("Enabled 1/1  ⚠ 2 hotkey conflicts  ⚠ 1 hotkey registration errors", vm.text)
    AssertTrue(vm.hasWarning)
}

Test_BuildStatusSummary_EmptyResult() {
    configs := []

    vm := BuildStatusSummary(configs, "")

    AssertEq("Enabled 0/0", vm.text)
    AssertFalse(vm.hasWarning)
}

Test_BuildMappingRows_ColumnFormatting() {
    mappings := [
        MakeMapping("RAlt", "F13", "^c", 1, 120, 40, 1)
    ]

    rows := BuildMappingRows(mappings)

    AssertEq(1, rows.Length)
    AssertEq(1, rows[1].idx)
    AssertEq("RAlt", rows[1].modifier)
    AssertEq("F13", rows[1].source)
    AssertEq("Ctrl+c", rows[1].target)
    AssertEq("Yes", rows[1].hold)
    AssertEq("Pass-through", rows[1].mode)
    AssertEq(120, rows[1].delay)
    AssertEq(40, rows[1].interval)
}

Test_BuildMappingRows_BlankTimingWithoutHold() {
    mappings := [
        MakeMapping("", "F13", "^c", 0, 300, 50, 0)
    ]

    rows := BuildMappingRows(mappings)

    AssertEq("", rows[1].modifier)
    AssertEq("No", rows[1].hold)
    AssertEq("", rows[1].mode)
    AssertEq("", rows[1].delay)
    AssertEq("", rows[1].interval)
}

Test_BuildMappingRows_KeyDisplay() {
    mappings := [
        MakeMapping("CapsLock", "WheelUp", "^+!#a", 0, 300, 50, 0)
    ]

    rows := BuildMappingRows(mappings)

    AssertEq("CapsLock", rows[1].modifier)
    AssertEq("WheelUp", rows[1].source)
    AssertEq("Ctrl+Shift+Alt+Win+a", rows[1].target)
    AssertEq("Intercept", rows[1].mode)
}

Test_BuildStatusDetails_ListsIssues() {
    result := MakeReloadResult(1, 2)
    result.conflicts[1].config2 := "IncludeCfg"

    details := BuildStatusDetails(result)

    AssertContains(details, "F13")
    AssertContains(details, "BadKey1")
    AssertContains(details, "BadKey2")
    AssertTrue(InStr(details, "`n") > 0, "Conflicts and reg errors should be separated by a newline.")
}

Test_BuildStatusDetails_Empty() {
    AssertEq("", BuildStatusDetails(MakeReloadResult()))
    AssertEq("", BuildStatusDetails(""))
}

Test_FormatProcessDisplay_LocalizedSummaries() {
    AssertEq("Scope: Global", FormatProcessDisplay("global", [], []))
    AssertEq("Scope: Only notepad.exe", FormatProcessDisplay("include", ["notepad.exe"], []))
    AssertEq("Scope: Only notepad.exe and 1 more", FormatProcessDisplay("include", ["notepad.exe", "code.exe"], []))
    AssertEq("Scope: Exclude notepad.exe", FormatProcessDisplay("exclude", [], ["notepad.exe"]))
    AssertEq("Scope: Exclude notepad.exe and 2 more", FormatProcessDisplay("exclude", [], ["notepad.exe", "code.exe", "devenv.exe"]))
    AssertEq("Scope: Global", FormatProcessDisplay("include", [], []))
}

Test_ConfigStore_OnChanged_ReceivesReloadResult() {
    store := ConfigStore.Instance
    notifications := []

    SeedConfigFile("NotifyCfg", "global", "", "", [], 1)
    LoadAllConfigs()
    store.Select("NotifyCfg")

    store.SetOnChanged((reloadResult) => notifications.Push(reloadResult))
    store.AddMapping(MakeMapping("", "F13", "^c"))

    ; One mutation -> exactly one notification carrying the reload result
    AssertEq(1, notifications.Length)
    AssertTrue(IsObject(notifications[1]), "Chokepoint notification should carry the ReloadAllHotkeys result.")
    AssertEq(0, notifications[1].regErrors.Length)

    store.SetOnChanged("")
}

Test_ConfigStore_Select_NotifiesRenderOnly() {
    store := ConfigStore.Instance
    notifications := []

    SeedConfigFile("RenderOnly", "global", "", "", [], 1)
    SeedConfigFile("Other", "global", "", "", [], 1)
    LoadAllConfigs()

    store.SetOnChanged((reloadResult) => notifications.Push(reloadResult))
    store.Select("RenderOnly")

    AssertEq(1, notifications.Length)
    AssertEq("", notifications[1], "Selection should notify render-only (no reload result).")
    AssertEq("RenderOnly", store.SelectedName)
    AssertEq("RenderOnly", ReadStateValue("State", "LastConfig"))

    store.SetOnChanged("")
}

Test_ConfigStore_Headless_NoRegistrationNeeded() {
    store := ConfigStore.Instance

    SeedConfigFile("HeadlessCfg", "global", "", "", [], 1)
    LoadAllConfigs()
    store.Select("HeadlessCfg")

    ; Headless: no OnChanged registration, mutations still complete fully
    store.SetEnabled(true)
    store.AddMapping(MakeMapping("", "F13", "^c"))

    AssertEq("HeadlessCfg", store.SelectedName)
    AssertEq(1, store.SelectedMappings().Length)
    AssertEq("F13", ReadConfigValue("HeadlessCfg", "Mapping1", "SourceKey"))
    AssertEq("1", ReadStateValue("EnabledConfigs", "HeadlessCfg"))
}
