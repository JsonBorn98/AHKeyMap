#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("DetectHotkeyConflicts reports scope overlap and Path B/C modifier conflicts", Test_DetectHotkeyConflicts_ReportsScopeAndModifierIssues)
RegisterTest("ReloadAllHotkeys tracks Path A/B/C registration state and cleanup", Test_ReloadAllHotkeys_TracksDispatchStateAndCleanup)
RegisterTest("RegisterPathCMapping stores mapping metadata for routed combos", Test_RegisterPathCMapping_StoresMappingMetadata)
RegisterTest("Path C wheel routing stays disabled without an active modifier session", Test_PathC_ShouldRouteWheelSource_FalseWithoutSession)
RegisterTest("Path C wheel routing stays disabled when the active session does not match scope", Test_PathC_ShouldRouteWheelSource_FalseWhenScopeDoesNotMatch)
RegisterTest("Path C wheel routing enables when an active session and scope-matching mapping exist", Test_PathC_ShouldRouteWheelSource_TrueWhenSessionAndScopeMatch)
RegisterTest("Path C falls back to the raw source key when no session matches", Test_PathC_SourceDown_FallsBackToRawSourceKey)
RegisterTest("Path C routed mappings dispatch target keys and mark the session as a gesture", Test_PathC_SourceDown_DispatchesMappedTarget)
RegisterTest("Path C wheel mappings dispatch target keys and mark the session as a gesture", Test_PathC_WheelSourceDown_DispatchesMappedTarget)
RegisterTest("Path C source key up stops repeat timers for matching mappings", Test_PathC_SourceUp_StopsActiveRepeats)
RegisterTest("Path C gesture completion dismisses the RButton menu with Escape", Test_PathC_ModUp_DismissesContextMenuAfterGesture)
RegisterTest("DetectHotkeyConflicts reports no conflict for disabled configs", Test_DetectHotkeyConflicts_NoConflictForDisabledConfigs)
RegisterTest("DetectHotkeyConflicts reports no conflict for disjoint scopes", Test_DetectHotkeyConflicts_NoConflictForDisjointScopes)
RegisterTest("Path C ModDown resets stale session before starting new one", Test_PathC_ModDown_ResetsStaleSession)

RunRegisteredTests()

Test_DetectHotkeyConflicts_ReportsScopeAndModifierIssues() {
    cfg1 := BuildConfigRecord("GlobalCfg", "global", "", "", true, [MakeMapping("", "F13", "^c")])
    cfg2 := BuildConfigRecord("IncludeCfg", "include", "notepad.exe", "", true, [MakeMapping("", "F13", "^v")])
    cfg3 := BuildConfigRecord("PathBCfg", "include", "notepad.exe", "", true, [MakeMapping("CapsLock", "F14", "^x", 0, 300, 50, 0)])
    cfg4 := BuildConfigRecord("PathCCfg", "include", "notepad.exe", "", true, [MakeMapping("CapsLock", "F15", "^z", 0, 300, 50, 1)])

    AllConfigs.Push(cfg1)
    AllConfigs.Push(cfg2)
    AllConfigs.Push(cfg3)
    AllConfigs.Push(cfg4)

    DetectHotkeyConflicts()

    AssertEq(2, HotkeyConflicts.Length)
    AssertEq("F13", HotkeyConflicts[1].hotkey)
    AssertEq("CapsLock (Path B/C conflict)", HotkeyConflicts[2].hotkey)
}

Test_ReloadAllHotkeys_TracksDispatchStateAndCleanup() {
    mappings := [
        MakeMapping("", "F21", "^c"),
        MakeMapping("CapsLock", "F22", "^v", 0, 300, 50, 0),
        MakeMapping("RAlt", "F23", "^x", 0, 300, 50, 1),
        MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1)
    ]
    AllConfigs.Push(BuildConfigRecord("DispatchCfg", "global", "", "", true, mappings))

    ReloadAllHotkeys()

    AssertTrue(ActiveHotkeys.Length >= 4)
    AssertEq(1, InterceptModKeys.Count)
    AssertMapHas(PathCMappingByModSource, "RAlt|F23")
    AssertMapHas(PathCMappingByModSource, "RButton|WheelUp")
    AssertMapHas(PathCModsUsed, "RAlt")
    AssertMapHas(PathCModsUsed, "RButton")
    AssertMapHas(PathCSourceKeysUsed, "F23")
    AssertMapHas(PathCSourceKeysUsed, "WheelUp")
    AssertEq(1, PathCWheelRoutePredicates.Length)
    AssertEq(0, HotkeyRegErrors.Length)

    UnregisterAllHotkeys()

    AssertEq(0, ActiveHotkeys.Length)
    AssertEq(0, InterceptModKeys.Count)
    AssertEq(0, HoldTimers.Count)
    AssertEq(0, PathCMappingByModSource.Count)
    AssertEq(0, PathCModSessions.Count)
    AssertEq(0, PathCModsUsed.Count)
    AssertEq(0, PathCSourceKeysUsed.Count)
    AssertEq(0, PathCWheelRoutePredicates.Length)
}

Test_RegisterPathCMapping_StoresMappingMetadata() {
    mapping := MakeMapping("RButton", "WheelUp", "^Tab", 1, 300, 50, 1)

    RegisterPathCMapping(mapping, "Cfg|1", "Cfg", "")

    AssertMapHas(PathCMappingByModSource, "RButton|WheelUp")
    entry := PathCMappingByModSource["RButton|WheelUp"][1]
    AssertEq("Cfg|1", entry.id)
    AssertEq("^Tab", entry.targetKey)
    AssertEq(1, entry.holdRepeat)
    AssertMapHas(PathCModsUsed, "RButton")
    AssertMapHas(PathCSourceKeysUsed, "WheelUp")
}

Test_PathC_ShouldRouteWheelSource_FalseWithoutSession() {
    RegisterPathCMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", "")

    AssertTrue(IsWheelSourceKey("WheelUp"))
    AssertTrue(IsWheelSourceKey("^WheelDown"))
    AssertFalse(IsWheelSourceKey("F13"))
    AssertFalse(PathC_ShouldRouteWheelSource("WheelUp"))
    AssertFalse(PathC_ShouldRouteWheelSource("WheelUp", "*WheelUp"))
}

Test_PathC_ShouldRouteWheelSource_FalseWhenScopeDoesNotMatch() {
    checker := (*) => false
    RegisterPathCMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", checker)
    PathC_ModDownCallback("RButton")

    AssertFalse(PathC_ShouldRouteWheelSource("WheelUp"))
    AssertFalse(PathC_ShouldRouteWheelSource("WheelUp", "*WheelUp"))
}

Test_PathC_ShouldRouteWheelSource_TrueWhenSessionAndScopeMatch() {
    checker := (*) => true
    RegisterPathCMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", checker)
    PathC_ModDownCallback("RButton")

    AssertTrue(PathC_ShouldRouteWheelSource("WheelUp"))
    AssertTrue(PathC_ShouldRouteWheelSource("WheelUp", "*WheelUp"))
}

Test_PathC_SourceDown_FallsBackToRawSourceKey() {
    EnableSendCapture()

    PathC_SourceDownCallback("F13")

    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("{F13}", CapturedSendKeys[1])
}

Test_PathC_SourceDown_DispatchesMappedTarget() {
    RegisterPathCMapping(MakeMapping("RButton", "F13", "^c", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    PathC_ModDownCallback("RButton")
    EnableSendCapture()

    PathC_SourceDownCallback("F13")

    session := PathC_GetSession("RButton")
    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^c", CapturedSendKeys[1])
    AssertEq("GestureActive", session.state)
    AssertTrue(session.isGesture)
}

Test_PathC_WheelSourceDown_DispatchesMappedTarget() {
    RegisterPathCMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    PathC_ModDownCallback("RButton")
    EnableSendCapture()

    PathC_SourceDownCallback("WheelUp")

    session := PathC_GetSession("RButton")
    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^{Tab}", CapturedSendKeys[1])
    AssertEq("GestureActive", session.state)
    AssertTrue(session.isGesture)
}

Test_PathC_SourceUp_StopsActiveRepeats() {
    mappingId := "Cfg|1"
    session := PathC_GetSession("RButton")
    session.state := "GestureActive"
    session.activeSources["F14"] := [mappingId]
    session.repeatMappings[mappingId] := true
    HoldTimers[mappingId] := {
        fn: NoOpTimer,
        startFn: NoOpTimer,
        interval: 50,
        active: true
    }

    PathC_SourceUpCallback("F14")

    AssertFalse(HoldTimers.Has(mappingId))
    AssertFalse(session.activeSources.Has("F14"))
    AssertFalse(session.repeatMappings.Has(mappingId))
}

Test_PathC_ModUp_DismissesContextMenuAfterGesture() {
    EnableSendCapture()
    session := PathC_GetSession("RButton")
    session.state := "GestureActive"
    session.isGesture := true

    PathC_ModUpCallback("RButton")
    WaitForCapturedSend("{Escape}", 400)

    AssertEq("Idle", session.state)
    AssertFalse(session.isGesture)
}

Test_DetectHotkeyConflicts_NoConflictForDisabledConfigs() {
    ; Two configs with same hotkey, but one is disabled
    cfg1 := BuildConfigRecord("Enabled", "global", "", "", true, [MakeMapping("", "F13", "^c")])
    cfg2 := BuildConfigRecord("Disabled", "global", "", "", false, [MakeMapping("", "F13", "^v")])

    AllConfigs.Push(cfg1)
    AllConfigs.Push(cfg2)

    DetectHotkeyConflicts()

    ; Disabled config should not produce a conflict
    AssertEq(0, HotkeyConflicts.Length)
}

Test_DetectHotkeyConflicts_NoConflictForDisjointScopes() {
    ; Two include configs with non-overlapping process lists
    cfg1 := BuildConfigRecord("BrowserCfg", "include", "chrome.exe", "", true, [MakeMapping("", "F13", "^c")])
    cfg2 := BuildConfigRecord("EditorCfg", "include", "notepad.exe", "", true, [MakeMapping("", "F13", "^v")])

    AllConfigs.Push(cfg1)
    AllConfigs.Push(cfg2)

    DetectHotkeyConflicts()

    ; Disjoint process scopes should not conflict
    AssertEq(0, HotkeyConflicts.Length)
}

Test_PathC_ModDown_ResetsStaleSession() {
    ; Start a session, leaving it in non-Idle state
    PathC_ModDownCallback("RButton")
    session := PathC_GetSession("RButton")
    AssertEq("HeldNoCombo", session.state)

    ; Mark session as having a gesture and active sources
    session.state := "GestureActive"
    session.isGesture := true
    session.activeSources["F13"] := ["Cfg|1"]

    ; Second ModDown without prior Up should reset
    PathC_ModDownCallback("RButton")
    session := PathC_GetSession("RButton")

    ; Session should be cleanly restarted
    AssertEq("HeldNoCombo", session.state)
    AssertFalse(session.isGesture)
    AssertEq(0, session.activeSources.Count)
    AssertEq(0, session.repeatMappings.Count)
}
