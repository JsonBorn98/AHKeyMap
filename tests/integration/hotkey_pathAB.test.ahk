#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("SendKeyCallback dispatches target key via DispatchSend", Test_PathA_SendKeyCallback_DispatchesTarget)
RegisterTest("HoldDownCallback initiates repeat timer and sends initial key", Test_PathA_HoldDown_InitiatesTimer)
RegisterTest("HoldUpCallback stops and removes the repeat timer", Test_PathA_HoldUp_StopsTimer)
RegisterTest("RestoreModKeyCallback sends keyboard modifier via DispatchSend", Test_PathB_RestoreModKey_SendsKeyboardModifier)
RegisterTest("RestoreModKeyCallback skips mouse modifier keys (BUG-010 regression)", Test_PathB_RestoreModKey_SkipsMouseModifier)
RegisterTest("Hold repeat timer lifecycle: create on down, remove on up", Test_PathB_ComboHoldRepeat_TimerLifecycle)

RunRegisteredTests()

; ============================================================================
; Test implementations
; ============================================================================

Test_PathA_SendKeyCallback_DispatchesTarget() {
    EnableSendCapture()

    SendKeyCallback("^c")

    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^c", CapturedSendKeys[1])
}

Test_PathA_HoldDown_InitiatesTimer() {
    EnableSendCapture()
    idx := "TestCfg|1"

    ; Call HoldDownCallback which should: send initial key + create timer
    HoldDownCallback("^c", 300, 50, idx, "F21")

    ; Initial send should be captured
    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("^c", CapturedSendKeys[1])

    ; Timer should be tracked in HoldTimers
    AssertMapHas(HoldTimers, idx)
    AssertTrue(HoldTimers[idx].active)

    ; Cleanup: stop the timer to avoid leaks
    StopHoldTimer(idx)
}

Test_PathA_HoldUp_StopsTimer() {
    EnableSendCapture()
    idx := "TestCfg|2"

    ; Start a hold timer
    HoldDownCallback("^v", 300, 50, idx, "F22")
    AssertMapHas(HoldTimers, idx)

    ; Release: should remove timer
    HoldUpCallback(idx)
    AssertMapNotHas(HoldTimers, idx)
}

Test_PathB_RestoreModKey_SendsKeyboardModifier() {
    EnableSendCapture()

    ; CapsLock is a keyboard key, should be restored
    RestoreModKeyCallback("CapsLock")

    AssertEq(1, CapturedSendKeys.Length)
    AssertEq("{CapsLock}", CapturedSendKeys[1])
}

Test_PathB_RestoreModKey_SkipsMouseModifier() {
    EnableSendCapture()

    ; Mouse buttons should NOT be sent (BUG-010: avoid unintended clicks)
    RestoreModKeyCallback("RButton")
    AssertEq(0, CapturedSendKeys.Length)

    RestoreModKeyCallback("MButton")
    AssertEq(0, CapturedSendKeys.Length)

    RestoreModKeyCallback("XButton1")
    AssertEq(0, CapturedSendKeys.Length)

    RestoreModKeyCallback("XButton2")
    AssertEq(0, CapturedSendKeys.Length)
}

Test_PathB_ComboHoldRepeat_TimerLifecycle() {
    EnableSendCapture()
    idx := "TestCfg|3"

    ; Simulate hold down: creates timer and sends initial key
    HoldDownCallback("^x", 300, 50, idx, "F23")
    AssertMapHas(HoldTimers, idx)
    AssertTrue(HoldTimers[idx].active)
    AssertEq(1, CapturedSendKeys.Length)

    ; Simulate hold up: removes timer
    HoldUpCallback(idx)
    AssertMapNotHas(HoldTimers, idx)

    ; Double-up should be safe (no error on missing idx)
    HoldUpCallback(idx)
    AssertMapNotHas(HoldTimers, idx)
}
