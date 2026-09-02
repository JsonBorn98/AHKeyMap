#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("DetectHotkeyConflicts reports scope overlap and Path B/C modifier conflicts", Test_DetectHotkeyConflicts_ReportsScopeAndModifierIssues)
RegisterTest("ReloadAllHotkeys registers Path A/B hotkeys and delegates Path C to the engine", Test_ReloadAllHotkeys_DelegatesPathCToEngineAndCleansUp)
RegisterTest("Path C wheel routing stays disabled without an active modifier session", Test_PathCEngine_ShouldRouteWheel_FalseWithoutSession)
RegisterTest("Path C wheel routing stays disabled when the active session does not match scope", Test_PathCEngine_ShouldRouteWheel_FalseWhenScopeDoesNotMatch)
RegisterTest("Path C wheel routing enables when an active session and scope-matching mapping exist", Test_PathCEngine_ShouldRouteWheel_TrueWhenSessionAndScopeMatch)
RegisterTest("Path C falls back to the raw source key when no session matches", Test_PathCEngine_SourceDown_FallsBackToRawSourceKey)
RegisterTest("Path C AddMapping ignores mappings that are not passthrough combos", Test_PathCEngine_AddMapping_IgnoresNonPathCMappings)
RegisterTest("Path C routed mappings dispatch target keys and mark the session as a gesture", Test_PathCEngine_SourceDown_DispatchesMappedTarget)
RegisterTest("Path C wheel mappings dispatch target keys and mark the session as a gesture", Test_PathCEngine_WheelSourceDown_DispatchesMappedTarget)
RegisterTest("Path C source key up stops repeat timers for matching mappings", Test_PathCEngine_SourceUp_StopsActiveRepeats)
RegisterTest("Path C gesture completion dismisses the RButton menu with Escape", Test_PathCEngine_ModUp_DismissesContextMenuAfterGesture)
RegisterTest("Path C ModDown resets stale session before starting new one", Test_PathCEngine_ModDown_ResetsStaleSession)
RegisterTest("Path C Commit registers routing hotkeys and Reset disables them again", Test_PathCEngine_CommitAndReset_RoundTrip)
RegisterTest("Path C Commit reports registration failures through its return value", Test_PathCEngine_Commit_ReportsRegErrors)
RegisterTest("DetectHotkeyConflicts reports no conflict for disabled configs", Test_DetectHotkeyConflicts_NoConflictForDisabledConfigs)
RegisterTest("DetectHotkeyConflicts reports no conflict for disjoint scopes", Test_DetectHotkeyConflicts_NoConflictForDisjointScopes)

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

    conflicts := DetectHotkeyConflicts()

    AssertEq(2, conflicts.Length)
    AssertEq("F13", conflicts[1].hotkey)
    AssertEq("CapsLock (Path B/C conflict)", conflicts[2].hotkey)
}

Test_ReloadAllHotkeys_DelegatesPathCToEngineAndCleansUp() {
    mappings := [
        MakeMapping("", "F21", "^c"),
        MakeMapping("CapsLock", "F22", "^v", 0, 300, 50, 0),
        MakeMapping("RAlt", "F23", "^x", 0, 300, 50, 1),
        MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1)
    ]
    AllConfigs.Push(BuildConfigRecord("DispatchCfg", "global", "", "", true, mappings))

    result := ReloadAllHotkeys()

    ; Path A/B registration bookkeeping stays in the shared globals
    AssertTrue(ActiveHotkeys.Length >= 3)
    AssertEq(1, InterceptModKeys.Count)

    ; Engine output arrives through the return value, not globals
    AssertEq(0, result.conflicts.Length)
    AssertEq(0, result.regErrors.Length)

    ; Path C behavior is reachable through the engine's public interface
    engine := PathCEngine.Instance
    AssertEq("Idle", engine.GetSessionState("RAlt"))
    AssertEq("Idle", engine.GetSessionState("RButton"))
    AssertFalse(engine.ShouldRouteWheel("WheelUp"))

    ; RAlt session: hold modifier, press source -> mapped target fires
    engine.OnModDown("RAlt")
    AssertEq("HeldNoCombo", engine.GetSessionState("RAlt"))
    EnableSendCapture()
    engine.OnSourceDown("F23")
    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^x", CapturedSendKeys[1])
    AssertEq("GestureActive", engine.GetSessionState("RAlt"))

    ; RButton wheel session: active session plus mapping enables wheel routing
    engine.OnModDown("RButton")
    AssertTrue(engine.ShouldRouteWheel("WheelUp"))
    engine.OnSourceDown("WheelUp")
    AssertEq("^{Tab}", CapturedSendKeys[2])
    AssertEq("GestureActive", engine.GetSessionState("RButton"))

    UnregisterAllHotkeys()

    ; Engine reset ends sessions and forgets all mappings
    AssertEq(0, ActiveHotkeys.Length)
    AssertEq(0, InterceptModKeys.Count)
    AssertEq(0, HoldTimers.Count)
    AssertEq("Idle", engine.GetSessionState("RAlt"))
    AssertEq("Idle", engine.GetSessionState("RButton"))
    AssertFalse(engine.ShouldRouteWheel("WheelUp"))
    DisableSendCapture()
}

Test_PathCEngine_ShouldRouteWheel_FalseWithoutSession() {
    engine := PathCEngine()
    engine.AddMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", "")

    AssertTrue(IsWheelSourceKey("WheelUp"))
    AssertTrue(IsWheelSourceKey("^WheelDown"))
    AssertFalse(IsWheelSourceKey("F13"))
    AssertFalse(engine.ShouldRouteWheel("WheelUp"))
    AssertFalse(engine.ShouldRouteWheel("WheelUp", "*WheelUp"))
}

Test_PathCEngine_ShouldRouteWheel_FalseWhenScopeDoesNotMatch() {
    engine := PathCEngine()
    cfg := BuildConfigRecord("Cfg", "include", "notepad.exe")
    checker := MakeProcessChecker(cfg)
    engine.AddMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", checker)
    engine.OnModDown("RButton")
    SetForegroundProcess("msedge.exe")

    AssertFalse(engine.ShouldRouteWheel("WheelUp"))
    AssertFalse(engine.ShouldRouteWheel("WheelUp", "*WheelUp"))
    engine.OnModUp("RButton")
}

Test_PathCEngine_ShouldRouteWheel_TrueWhenSessionAndScopeMatch() {
    engine := PathCEngine()
    cfg := BuildConfigRecord("Cfg", "include", "notepad.exe")
    checker := MakeProcessChecker(cfg)
    engine.AddMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", checker)
    engine.OnModDown("RButton")
    SetForegroundProcess("notepad.exe")

    AssertTrue(engine.ShouldRouteWheel("WheelUp"))
    AssertTrue(engine.ShouldRouteWheel("WheelUp", "*WheelUp"))
    engine.OnModUp("RButton")
}

Test_PathCEngine_SourceDown_FallsBackToRawSourceKey() {
    engine := PathCEngine()
    EnableSendCapture()

    engine.OnSourceDown("F13")

    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("{F13}", CapturedSendKeys[1])
}

Test_PathCEngine_AddMapping_IgnoresNonPathCMappings() {
    engine := PathCEngine()
    EnableSendCapture()

    ; Path A (no modifier) and Path B (no passthrough) shapes must be ignored
    engine.AddMapping(MakeMapping("", "F13", "^c", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    engine.AddMapping(MakeMapping("RButton", "F14", "^v", 0, 300, 50, 0), "Cfg|2", "Cfg", "")

    engine.OnModDown("RButton")
    engine.OnSourceDown("F13")
    engine.OnSourceDown("F14")

    ; Neither mapping is registered, so both presses fall back to their raw keys
    AssertEq(2, CapturedSendKeys.Length)
    AssertEq("{F13}", CapturedSendKeys[1])
    AssertEq("{F14}", CapturedSendKeys[2])
    AssertEq("HeldNoCombo", engine.GetSessionState("RButton"))
    engine.OnModUp("RButton")
}

Test_PathCEngine_SourceDown_DispatchesMappedTarget() {
    engine := PathCEngine()
    engine.AddMapping(MakeMapping("RButton", "F13", "^c", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    engine.OnModDown("RButton")
    EnableSendCapture()

    engine.OnSourceDown("F13")

    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^c", CapturedSendKeys[1])
    AssertEq("GestureActive", engine.GetSessionState("RButton"))
    engine.OnModUp("RButton")
}

Test_PathCEngine_WheelSourceDown_DispatchesMappedTarget() {
    engine := PathCEngine()
    engine.AddMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    engine.OnModDown("RButton")
    EnableSendCapture()

    engine.OnSourceDown("WheelUp")

    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^{Tab}", CapturedSendKeys[1])
    AssertEq("GestureActive", engine.GetSessionState("RButton"))
    engine.OnModUp("RButton")
}

Test_PathCEngine_SourceUp_StopsActiveRepeats() {
    engine := PathCEngine()
    ; Hold-repeat mapping: immediate send on press, then repeats after the delay
    engine.AddMapping(MakeMapping("RButton", "F14", "^v", 1, 200, 50, 1), "Cfg|1", "Cfg", "")
    engine.OnModDown("RButton")
    EnableSendCapture()

    engine.OnSourceDown("F14")
    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^v", CapturedSendKeys[1])
    AssertEq("GestureActive", engine.GetSessionState("RButton"))

    ; Release the source key: no further sends may occur within the repeat window
    engine.OnSourceUp("F14")
    Sleep 400
    AssertEq(1, CapturedSendKeys.Length)

    ; Re-pressing the source still triggers the mapping (nothing got stuck)
    engine.OnSourceDown("F14")
    AssertEq(2, CapturedSendKeys.Length)
    AssertEq("^v", CapturedSendKeys[2])

    engine.OnSourceUp("F14")
    engine.OnModUp("RButton")
    AssertEq("Idle", engine.GetSessionState("RButton"))
}

Test_PathCEngine_ModUp_DismissesContextMenuAfterGesture() {
    engine := PathCEngine()
    engine.AddMapping(MakeMapping("RButton", "F13", "^c", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    engine.OnModDown("RButton")
    EnableSendCapture()

    ; Trigger a gesture so the session is marked as a gesture session
    engine.OnSourceDown("F13")
    AssertEq("GestureActive", engine.GetSessionState("RButton"))

    engine.OnModUp("RButton")
    WaitForCapturedSend("{Escape}", 400)

    AssertEq("Idle", engine.GetSessionState("RButton"))
}

Test_PathCEngine_ModDown_ResetsStaleSession() {
    engine := PathCEngine()
    engine.AddMapping(MakeMapping("RButton", "F13", "^c", 0, 300, 50, 1), "Cfg|1", "Cfg", "")

    ; Capture sends: OnSourceDown dispatches the mapped target key, and an
    ; uncaptured dispatch ships a real Ctrl+C into the foreground window
    ; (it once killed a running build with a Terminate batch job prompt)
    EnableSendCapture()

    ; Start a session and let it trigger a gesture
    engine.OnModDown("RButton")
    AssertEq("HeldNoCombo", engine.GetSessionState("RButton"))
    engine.OnSourceDown("F13")
    AssertEq("GestureActive", engine.GetSessionState("RButton"))
    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^c", CapturedSendKeys[1])

    ; Second ModDown without prior Up should cleanly restart the session
    engine.OnModDown("RButton")

    AssertEq("HeldNoCombo", engine.GetSessionState("RButton"))
    engine.OnModUp("RButton")
}

Test_PathCEngine_CommitAndReset_RoundTrip() {
    engine := PathCEngine()
    engine.AddMapping(MakeMapping("RButton", "WheelUp", "^Tab", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    engine.AddMapping(MakeMapping("RAlt", "F23", "^x", 0, 300, 50, 1), "Cfg|2", "Cfg", "")

    ; Commit registers the routing hotkeys without errors
    regErrors := engine.Commit()
    AssertEq(0, regErrors.Length)

    ; Reset disables them and clears all mapping state
    engine.Reset()
    engine.OnModDown("RButton")
    AssertFalse(engine.ShouldRouteWheel("WheelUp"))
    AssertEq("HeldNoCombo", engine.GetSessionState("RButton"))
    engine.OnModUp("RButton")
    AssertEq("Idle", engine.GetSessionState("RButton"))
}

Test_PathCEngine_Commit_ReportsRegErrors() {
    engine := PathCEngine()
    ; Invalid key names must fail registration and surface in the returned error list
    engine.AddMapping(MakeMapping("RButton", "NotARealKey", "^c", 0, 300, 50, 1), "Cfg|1", "Cfg", "")
    regErrors := engine.Commit()

    AssertEq(2, regErrors.Length)
    AssertArrayContains(regErrors, "*NotARealKey")
    AssertArrayContains(regErrors, "*NotARealKey Up")

    engine.Reset()
}

Test_DetectHotkeyConflicts_NoConflictForDisabledConfigs() {
    ; Two configs with same hotkey, but one is disabled
    cfg1 := BuildConfigRecord("Enabled", "global", "", "", true, [MakeMapping("", "F13", "^c")])
    cfg2 := BuildConfigRecord("Disabled", "global", "", "", false, [MakeMapping("", "F13", "^v")])

    AllConfigs.Push(cfg1)
    AllConfigs.Push(cfg2)

    conflicts := DetectHotkeyConflicts()

    ; Disabled config should not produce a conflict
    AssertEq(0, conflicts.Length)
}

Test_DetectHotkeyConflicts_NoConflictForDisjointScopes() {
    ; Two include configs with non-overlapping process lists
    cfg1 := BuildConfigRecord("BrowserCfg", "include", "chrome.exe", "", true, [MakeMapping("", "F13", "^c")])
    cfg2 := BuildConfigRecord("EditorCfg", "include", "notepad.exe", "", true, [MakeMapping("", "F13", "^v")])

    AllConfigs.Push(cfg1)
    AllConfigs.Push(cfg2)

    conflicts := DetectHotkeyConflicts()

    ; Disjoint process scopes should not conflict
    AssertEq(0, conflicts.Length)
}
