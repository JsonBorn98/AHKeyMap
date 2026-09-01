#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

RegisterTest("Main GUI smoke flow covers config lifecycle and persisted state", Test_MainGui_SmokeFlow_CoversLifecycle)

RunRegisteredTests()

Test_MainGui_SmokeFlow_CoversLifecycle() {
    store := ConfigStore.Instance
    StartApp()

    AssertTrue(MainGui != "")
    AssertEq("en-US", CurrentLangCode)
    AssertEq(0, AllConfigs.Length)
    AssertEq("", store.SelectedName)
    AssertTrue(InStr(WinGetTitle("ahk_id " MainGui.Hwnd), "AHKeyMap v" APP_VERSION) > 0)

    OnNewConfig()
    newGui := GetGuiByTitle(L("GuiEvents.NewConfig.Title"))
    newGui["ConfigName"].Value := "SmokeConfig"
    OnNewConfigOK(newGui)

    AssertFileExists(CONFIG_DIR "\SmokeConfig.ini")
    AssertEq("SmokeConfig", store.SelectedName)
    AssertEq(1, AllConfigs.Length)
    AssertEq("1", ReadStateValue("EnabledConfigs", "SmokeConfig"))
    AssertEq("SmokeConfig", ReadStateValue("State", "LastConfig"))

    EditingIndex := 0
    ShowEditMappingGui()
    EditModifierEdit.ahkKey := "RAlt"
    EditModifierEdit.Value := KeyToDisplay("RAlt")
    UpdatePassthroughState()
    EditSourceEdit.ahkKey := "F13"
    EditSourceEdit.Value := KeyToDisplay("F13")
    EditTargetEdit.ahkKey := "^c"
    EditTargetEdit.Value := KeyToDisplay("^c")
    EditHoldRepeatCB.Value := 1
    OnHoldRepeatToggle(EditHoldRepeatCB)
    EditDelayEdit.Value := "120"
    EditIntervalEdit.Value := "30"
    EditPassthroughCB.Value := 1
    OnEditMappingOK()

    cfg := LoadConfigData("SmokeConfig")
    AssertEq(1, cfg["mappings"].Length)
    AssertEq("RAlt", cfg["mappings"][1]["ModifierKey"])
    AssertEq("F13", cfg["mappings"][1]["SourceKey"])
    AssertEq("^c", cfg["mappings"][1]["TargetKey"])
    AssertEq(1, cfg["mappings"][1]["PassthroughMod"])
    AssertEq(1, MappingLV.GetCount())

    EnabledCB.Value := 0
    OnToggleEnabled(EnabledCB)
    AssertFalse(store.Selected()["enabled"])
    AssertEq("0", ReadStateValue("EnabledConfigs", "SmokeConfig"))

    OnChangeProcess()
    changeGui := GetGuiByTitle(L("GuiEvents.ChangeScope.Title"))
    ; The dialog opens in global mode with the process editor disabled. Setting .Value
    ; does not raise Click, so send BM_CLICK (0xF5) to check the radio and fire the
    ; real Click handler; actual mouse clicks are flaky in CI.
    AssertFalse(changeGui["ProcName"].Enabled, "Process editor should start disabled in global mode.")
    SendMessage(0xF5, 0, 0, changeGui["ScopeIncludeRadio"].Hwnd)
    WaitForCondition((*) => changeGui["ProcName"].Enabled, 250, 10, "Include scope editor did not enable the process list input.")
    AssertTrue(changeGui["ScopeIncludeRadio"].Value, "Include radio should be checked after BM_CLICK.")
    changeGui["ProcName"].Value := "notepad.exe`ncode.exe"
    OnChangeProcessOK(changeGui)

    AssertEq("include", store.Selected()["processMode"])
    AssertEq("notepad.exe|code.exe", store.Selected()["process"])
    AssertEq("Scope: Only notepad.exe and 1 more", ProcessText.Value)
    AssertEq("include", ReadConfigValue("SmokeConfig", "Meta", "ProcessMode"))
    AssertEq("notepad.exe|code.exe", ReadConfigValue("SmokeConfig", "Meta", "Process"))

    EnabledCB.Value := 1
    OnToggleEnabled(EnabledCB)
    AssertTrue(store.Selected()["enabled"])
    AssertEq("1", ReadStateValue("EnabledConfigs", "SmokeConfig"))
    ; Note: this sandbox cannot deliver the physical key state that Path A/B/C
    ; registration depends on, so ActiveHotkeys stays 0 here (the baseline test
    ; had the same limitation; hotkey registration is covered by integration
    ; tests and manual verification).

    ; OnDeleteConfig shows a blocking confirmation MsgBox; arm an in-script
    ; timer to click its Yes button (Button1) shortly after it opens, because
    ; SendInput from outside the process is not delivered in this sandbox.
    SetTimer(() => (
        hwnd := WinExist(APP_NAME " ahk_class #32770"),
        hwnd != 0 ? ControlClick("Button1", hwnd) : 0
    ), -1000)
    OnDeleteConfig()

    AssertFalse(FileExist(CONFIG_DIR "\SmokeConfig.ini"))
    AssertEq(0, AllConfigs.Length)
    AssertEq("", store.SelectedName)
}
