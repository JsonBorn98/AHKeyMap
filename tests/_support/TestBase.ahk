#Requires AutoHotkey v2.0

global TestCases := []
global TestResults := []
global CapturedSendKeys := []

RegisterTest(name, fn) {
    TestCases.Push({
        name: name,
        fn: fn
    })
}

RunRegisteredTests() {
    passCount := 0
    failCount := 0

    InitializeTestSuite()

    for _, testCase in TestCases {
        ResetTestSandbox()
        startTick := A_TickCount

        try {
            testCase.fn.Call()
            durationMs := A_TickCount - startTick
            TestResults.Push({
                name: testCase.name,
                status: "pass",
                durationMs: durationMs
            })
            LogTestLine(Format("PASS {1} ({2} ms)", testCase.name, durationMs))
            passCount++
        } catch as e {
            durationMs := A_TickCount - startTick
            TestResults.Push({
                name: testCase.name,
                status: "fail",
                durationMs: durationMs,
                message: FormatErrorMessage(e)
            })
            LogTestLine(Format("FAIL {1} ({2} ms): {3}", testCase.name, durationMs, FormatErrorMessage(e)))
            failCount++
        } finally {
            try CleanupAfterTest()
        }
    }

    CleanupAfterSuite()
    LogTestLine(Format("SUMMARY pass={1} fail={2}", passCount, failCount))
    ExitApp(failCount > 0 ? 1 : 0)
}

InitializeTestSuite() {
    global CurrentLangCode := "en-US"
    global DispatchSendHook := ""
    ResetTestSandbox()
}

ResetTestSandbox() {
    CleanupTestWindows()
    ResetTestConfigDir()
    ResetAppState()
    DisableSendCapture()
}

CleanupAfterTest() {
    CleanupTestWindows()
    DisableSendCapture()
    try UnregisterAllHotkeys()
}

CleanupAfterSuite() {
    CleanupTestWindows()
    DisableSendCapture()
    try UnregisterAllHotkeys()
}

ResetTestConfigDir() {
    if DirExist(CONFIG_DIR)
        DirDelete(CONFIG_DIR, 1)
    DirCreate(CONFIG_DIR)
}

ResetAppState() {
    global AllConfigs
    global CurrentConfigName
    global CurrentConfigFile
    global CurrentProcessMode
    global CurrentProcess
    global CurrentProcessList
    global CurrentExcludeProcess
    global CurrentExcludeProcessList
    global CurrentConfigEnabled
    global Mappings
    global MainGui
    global ConfigDDL
    global EnabledCB
    global ProcessText
    global MappingLV
    global StatusText
    global StatusDetailLink
    global StatusHasWarning
    global StatusDetailHovered
    global BtnAddMapping
    global BtnEditMapping
    global BtnCopyMapping
    global BtnDeleteMapping
    global BtnRunAsAdmin
    global EditGui
    global EditModifierEdit
    global EditSourceEdit
    global EditTargetEdit
    global EditHoldRepeatCB
    global EditDelayEdit
    global EditIntervalEdit
    global EditPassthroughCB
    global EditingIndex
    global ActiveHotkeys
    global HoldTimers
    global InterceptModKeys
    global AllProcessCheckers
    global HotkeyConflicts
    global HotkeyRegErrors
    global PathCMappingByModSource
    global PathCModSessions
    global PathCModsUsed
    global PathCSourceKeysUsed
    global CaptureTarget
    global CaptureGui
    global CaptureDisplayText
    global CaptureTimer
    global CaptureKeys
    global CaptureHadKeys
    global CaptureMouseKeys
    global ProcessPickerOpen
    global ProcessPickerGui
    global CurrentLangCode
    global DispatchSendHook

    AllConfigs.Length := 0
    CurrentConfigName := ""
    CurrentConfigFile := ""
    CurrentProcessMode := "global"
    CurrentProcess := ""
    CurrentProcessList := []
    CurrentExcludeProcess := ""
    CurrentExcludeProcessList := []
    CurrentConfigEnabled := true
    Mappings.Length := 0

    MainGui := ""
    ConfigDDL := ""
    EnabledCB := ""
    ProcessText := ""
    MappingLV := ""
    StatusText := ""
    StatusDetailLink := ""
    StatusHasWarning := false
    StatusDetailHovered := false
    BtnAddMapping := ""
    BtnEditMapping := ""
    BtnCopyMapping := ""
    BtnDeleteMapping := ""
    BtnRunAsAdmin := ""

    EditGui := ""
    EditModifierEdit := ""
    EditSourceEdit := ""
    EditTargetEdit := ""
    EditHoldRepeatCB := ""
    EditDelayEdit := ""
    EditIntervalEdit := ""
    EditPassthroughCB := ""
    EditingIndex := 0

    ActiveHotkeys.Length := 0
    ClearMap(HoldTimers)
    ClearMap(InterceptModKeys)
    AllProcessCheckers.Length := 0
    HotkeyConflicts.Length := 0
    HotkeyRegErrors.Length := 0
    ClearMap(PathCMappingByModSource)
    ClearMap(PathCModSessions)
    ClearMap(PathCModsUsed)
    ClearMap(PathCSourceKeysUsed)

    CaptureTarget := ""
    CaptureGui := ""
    CaptureDisplayText := ""
    CaptureTimer := ""
    CaptureKeys.Length := 0
    CaptureHadKeys := false
    ClearMap(CaptureMouseKeys)

    ProcessPickerOpen := false
    ProcessPickerGui := ""
    CurrentLangCode := "en-US"
    DispatchSendHook := ""
}

CleanupTestWindows() {
    global MainGui
    global EditGui
    global CaptureGui
    global ProcessPickerGui
    global ProcessPickerOpen

    if (CaptureGui != "") {
        try CaptureGui.Destroy()
        CaptureGui := ""
    }

    if (EditGui != "") {
        try {
            if (MainGui != "")
                MainGui.Opt("-Disabled")
        }
        try EditGui.Destroy()
        EditGui := ""
    }

    if (ProcessPickerGui != "") {
        try ProcessPickerGui.Destroy()
        ProcessPickerGui := ""
    }
    ProcessPickerOpen := false

    if (MainGui != "") {
        try MainGui.Destroy()
        MainGui := ""
    }
}

ClearMap(mapObj) {
    keys := []
    for key, _ in mapObj
        keys.Push(key)
    for _, key in keys
        mapObj.Delete(key)
}

FormatValue(value) {
    valueType := Type(value)
    if (valueType = "Array") {
        parts := []
        for _, item in value
            parts.Push(FormatValue(item))
        return "[" JoinValues(parts, ", ") "]"
    }

    if (valueType = "Map") {
        parts := []
        for key, item in value
            parts.Push(Format("{1}: {2}", FormatValue(key), FormatValue(item)))
        return "{" JoinValues(parts, ", ") "}"
    }

    if (value == "")
        return "<empty>"
    return String(value)
}

JoinValues(values, separator) {
    result := ""
    for index, value in values {
        if (index > 1)
            result .= separator
        result .= value
    }
    return result
}

Fail(message) {
    throw Error(message)
}

AssertTrue(condition, message := "") {
    if !condition
        Fail(message != "" ? message : "Expected condition to be true.")
}

AssertFalse(condition, message := "") {
    if condition
        Fail(message != "" ? message : "Expected condition to be false.")
}

AssertEq(expected, actual, message := "") {
    expectedValue := FormatValue(expected)
    actualValue := FormatValue(actual)
    if (expectedValue != actualValue) {
        if (message = "")
            message := Format("Expected {1}, got {2}.", expectedValue, actualValue)
        Fail(message)
    }
}

AssertMapHas(mapObj, key, message := "") {
    if !mapObj.Has(key) {
        if (message = "")
            message := Format("Expected map to contain key {1}.", FormatValue(key))
        Fail(message)
    }
}

AssertFileExists(path, message := "") {
    if !FileExist(path) {
        if (message = "")
            message := Format("Expected file to exist: {1}", path)
        Fail(message)
    }
}

MakeMapping(modifierKey, sourceKey, targetKey, holdRepeat := 0, repeatDelay := 300, repeatInterval := 50, passthroughMod := 0) {
    mapping := Map()
    mapping["ModifierKey"] := modifierKey
    mapping["SourceKey"] := sourceKey
    mapping["TargetKey"] := targetKey
    mapping["HoldRepeat"] := holdRepeat
    mapping["RepeatDelay"] := repeatDelay
    mapping["RepeatInterval"] := repeatInterval
    mapping["PassthroughMod"] := passthroughMod
    return mapping
}

BuildConfigRecord(configName, processMode := "global", process := "", excludeProcess := "", enabled := true, mappings := "") {
    cfg := Map()
    cfg["name"] := configName
    cfg["file"] := CONFIG_DIR "\" configName ".ini"
    cfg["processMode"] := processMode
    cfg["process"] := process
    cfg["processList"] := ParseProcessList(process)
    cfg["excludeProcess"] := excludeProcess
    cfg["excludeProcessList"] := ParseProcessList(excludeProcess)
    cfg["enabled"] := enabled
    cfg["mappings"] := mappings = "" ? [] : mappings
    return cfg
}

SeedConfigFile(configName, processMode := "global", process := "", excludeProcess := "", mappings := "", enabled := 1) {
    configFile := CONFIG_DIR "\" configName ".ini"

    IniWrite(configName, configFile, "Meta", "Name")
    IniWrite(processMode, configFile, "Meta", "ProcessMode")
    IniWrite(process, configFile, "Meta", "Process")
    IniWrite(excludeProcess, configFile, "Meta", "ExcludeProcess")

    if (mappings != "") {
        for idx, mapping in mappings {
            sectionName := "Mapping" idx
            IniWrite(mapping["ModifierKey"], configFile, sectionName, "ModifierKey")
            IniWrite(mapping["SourceKey"], configFile, sectionName, "SourceKey")
            IniWrite(mapping["TargetKey"], configFile, sectionName, "TargetKey")
            IniWrite(mapping["HoldRepeat"], configFile, sectionName, "HoldRepeat")
            IniWrite(mapping["RepeatDelay"], configFile, sectionName, "RepeatDelay")
            IniWrite(mapping["RepeatInterval"], configFile, sectionName, "RepeatInterval")
            IniWrite(mapping["PassthroughMod"], configFile, sectionName, "PassthroughMod")
        }
    }

    IniWrite(enabled, STATE_FILE, "EnabledConfigs", configName)
    return configFile
}

ReadConfigValue(configName, section, key, defaultValue := "") {
    return IniRead(CONFIG_DIR "\" configName ".ini", section, key, defaultValue)
}

ReadStateValue(section, key, defaultValue := "") {
    return IniRead(STATE_FILE, section, key, defaultValue)
}

EnableSendCapture() {
    global DispatchSendHook := Func("RecordCapturedSend")
    global CapturedSendKeys
    CapturedSendKeys.Length := 0
}

DisableSendCapture() {
    global DispatchSendHook := ""
    global CapturedSendKeys
    CapturedSendKeys.Length := 0
}

RecordCapturedSend(sendKey) {
    CapturedSendKeys.Push(sendKey)
}

WaitForCondition(predicate, timeoutMs := 1000, pollIntervalMs := 25, failureMessage := "Timed out waiting for condition.") {
    startTick := A_TickCount
    while ((A_TickCount - startTick) <= timeoutMs) {
        if predicate.Call()
            return true
        Sleep(pollIntervalMs)
    }

    Fail(failureMessage)
}

WaitForWindow(windowTitle, timeoutMs := 1000) {
    predicate := (*) => WinExist(windowTitle)
    WaitForCondition(predicate, timeoutMs, 25, Format("Timed out waiting for window '{1}'.", windowTitle))
    return WinExist(windowTitle)
}

GetGuiByTitle(windowTitle, timeoutMs := 1000) {
    hwnd := WaitForWindow(windowTitle, timeoutMs)
    return GuiFromHwnd(hwnd)
}

WaitForCapturedSend(sendKey, timeoutMs := 250) {
    predicate := (*) => HasCapturedSend(sendKey)
    WaitForCondition(predicate, timeoutMs, 10, Format("Expected send '{1}' was not captured.", sendKey))
}

HasCapturedSend(sendKey) {
    for _, capturedKey in CapturedSendKeys {
        if (capturedKey = sendKey)
            return true
    }
    return false
}

NoOpTimer(*) {
}

FormatErrorMessage(err) {
    message := err.Message
    try {
        if (err.What != "")
            message .= " [" err.What "]"
    }
    try {
        if (err.Line != "")
            message .= " line " err.Line
    }
    return message
}

LogTestLine(message) {
    FileAppend(message "`n", "*")
}
