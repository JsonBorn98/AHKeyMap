; ============================================================================
; AHKeyMap - AHKv2 key & mouse remapping tool
; Supports multiple configs, per-process scopes, key capture, combo mappings,
; long-press repeat, custom modifiers (including mouse buttons), wheel remap,
; passthrough combos, and three-state process scopes (global/include/exclude).
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

;@Ahk2Exe-SetName AHKeyMap
;@Ahk2Exe-SetDescription AHKeyMap - Key remapping tool
;@Ahk2Exe-SetVersion 2.8.1
;@Ahk2Exe-SetCopyright Copyright (c) 2026
;@Ahk2Exe-SetMainIcon ..\assets\icon.ico

; ============================================================================
; Global variables (shared across all modules)
; ============================================================================
if !IsSet(__AHKM_TEST_MODE)
    global __AHKM_TEST_MODE := false
if !IsSet(__AHKM_CONFIG_DIR)
    global __AHKM_CONFIG_DIR := ""

global APP_NAME := "AHKeyMap"
global APP_VERSION := "2.8.1"
global SCRIPT_DIR := A_ScriptDir
global APP_ROOT := (A_IsCompiled ? SCRIPT_DIR : SCRIPT_DIR "\..")
global CONFIG_DIR := (__AHKM_CONFIG_DIR != "" ? __AHKM_CONFIG_DIR : APP_ROOT "\configs")
global STATE_FILE := CONFIG_DIR "\_state.ini"
global REG_RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global REG_VALUE_NAME := "AHKeyMap"

; Localization globals
global CurrentLangCode := ""   ; e.g. "en-US" or "zh-CN"

; Timer-related constants and default values
global CAPTURE_START_DELAY := 200       ; key capture start delay (ms)
global CAPTURE_POLL_INTERVAL := 30      ; key capture polling interval (ms)
global CONTEXT_MENU_DISMISS_DELAY := 10 ; context menu dismissal delay (ms)
global DEFAULT_REPEAT_DELAY := 300      ; default long-press delay (ms)
global DEFAULT_REPEAT_INTERVAL := 50    ; default long-press interval (ms)

; Config-related globals
global AllConfigs := []
global CurrentConfigName := ""
global CurrentConfigFile := ""
global CurrentProcessMode := "global"
global CurrentProcess := ""
global CurrentProcessList := []
global CurrentExcludeProcess := ""
global CurrentExcludeProcessList := []
global CurrentConfigEnabled := true
global Mappings := []

; GUI control references
global MainGui := ""
global ConfigDDL := ""
global EnabledCB := ""
global ProcessText := ""
global MappingLV := ""
global StatusText := ""
global StatusDetailLink := ""
global StatusHasWarning := false
global StatusDetailHovered := false
global BtnAddMapping := ""
global BtnEditMapping := ""
global BtnCopyMapping := ""
global BtnDeleteMapping := ""
global BtnRunAsAdmin := ""
global EditGui := ""
global EditModifierEdit := ""
global EditSourceEdit := ""
global EditTargetEdit := ""
global EditHoldRepeatCB := ""
global EditDelayEdit := ""
global EditIntervalEdit := ""
global EditPassthroughCB := ""
global EditingIndex := 0

; Hotkey engine globals
global ActiveHotkeys := []
global HoldTimers := Map()
global InterceptModKeys := Map()
global AllProcessCheckers := []
global HotkeyConflicts := []
global HotkeyRegErrors := []
global PathCMappingByModSource := Map()
global PathCModSessions := Map()
global PathCModsUsed := Map()
global PathCSourceKeysUsed := Map()
global DispatchSendHook := ""

; Key capture globals
global IsCapturing := false
global CaptureTarget := ""
global CaptureGui := ""
global CaptureDisplayText := ""
global CaptureTimer := ""
global CaptureKeys := []
global CaptureHadKeys := false
global CaptureMouseKeys := Map()

; Process picker globals
global ProcessPickerOpen := false
global ProcessPickerGui := ""

; ============================================================================
; Include modules
; ============================================================================
#Include "core/Config.ahk"
#Include "shared/Utils.ahk"
#Include "core/Localization.ahk"
#Include "core/HotkeyEngine.ahk"
#Include "core/KeyCapture.ahk"
#Include "ui/GuiMain.ahk"
#Include "ui/MappingEditor.ahk"
#Include "ui/GuiEvents.ahk"


; ============================================================================
; Tray and window event handlers
; ============================================================================

OnMainClose(thisGui) {
    thisGui.Hide()
}

OnTrayShow(*) {
    MainGui.Show()
}

OnTrayExit(*) {
    UnregisterAllHotkeys()
    ExitApp()
}

; Toggle auto-start from tray menu
OnTrayAutoStartToggle(*) {
    if IsAutoStartEnabled() {
        DisableAutoStart()
        A_TrayMenu.Uncheck(L("Tray.AutoStart"))
    } else {
        EnableAutoStart()
        A_TrayMenu.Check(L("Tray.AutoStart"))
    }
}

OnRunAsAdmin(*) {
    if A_IsAdmin {
        MsgBox(L("General.AlreadyAdmin"), APP_NAME, "Icon!")
        return
    }
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
        ExitApp()
    } catch as e {
        MsgBox(Format(L("General.ElevateFailed"), e.Message), APP_NAME, "Icon!")
    }
}

OnTraySetLanguage(langCode) {
    global CurrentLangCode
    if (CurrentLangCode = langCode)
        return
    CurrentLangCode := langCode
    ; Persist UILanguage into _state.ini
    SaveEnabledStates()

    ; Soft-reload main window in the new language
    RebuildMainWindowForLanguageChange()
}

; ============================================================================
; Application entry point
; ============================================================================
if !__AHKM_TEST_MODE
    StartApp()

StartApp() {
    global CurrentLangCode

    ; Ensure config directory exists
    if !DirExist(CONFIG_DIR)
        DirCreate(CONFIG_DIR)

    ; Load last used config and UI language (for GUI initialization)
    lastConfig := ""
    if FileExist(STATE_FILE) {
        lastConfig := IniRead(STATE_FILE, "State", "LastConfig", "")
        langFromState := IniRead(STATE_FILE, "State", "UILanguage", "")
        if (langFromState != "")
            CurrentLangCode := langFromState
    }

    ; On first run or when UILanguage is missing, default UI language to English
    if (CurrentLangCode = "")
        CurrentLangCode := "en-US"

    ; Build main GUI
    BuildMainGui()

    ; Load all configs into AllConfigs
    LoadAllConfigs()

    ; At startup, sync enabled states and clean stale keys in _state.ini
    SaveEnabledStates()

    ; Refresh config dropdown (GUI only)
    RefreshConfigList(lastConfig)

    ; Register hotkeys for all enabled configs
    ReloadAllHotkeys()

    ; Show main window
    MainGui.Show("w720 h500")
}

; Rebuild main window for language switch (soft reload)
RebuildMainWindowForLanguageChange() {
    global MainGui
    global CurrentConfigName
    global EditGui
    global CaptureGui
    global ProcessPickerOpen
    global ProcessPickerGui

    ; Record current config name and window position/size
    currentConfig := CurrentConfigName
    x := 0, y := 0, w := 0, h := 0
    try {
        if (MainGui != "")
            MainGui.GetPos(&x, &y, &w, &h)
    }

    ; Close any open child/modal windows
    if (EditGui != "") {
        try DestroyModalGui(EditGui)
        EditGui := ""
    }
    if (CaptureGui != "") {
        try CancelCapture()
    }
    if (ProcessPickerOpen && ProcessPickerGui != "") {
        try CloseProcessPicker(ProcessPickerGui)
        ProcessPickerGui := ""
    }

    ; Destroy old main window
    if (MainGui != "") {
        try MainGui.Opt("-Disabled")
        try MainGui.Hide()
        try MainGui.Destroy()
        MainGui := ""
    }

    ; Rebuild main window and tray menu using current language
    BuildMainGui()

    ; Refresh config list and GUI state with the previously selected config
    ; Clear CurrentConfigName so OnConfigSelect reloads config and mapping list
    global CurrentConfigName
    CurrentConfigName := ""
    RefreshConfigList(currentConfig)

    ; Refresh status bar with the new language
    UpdateStatusText()

    ; Restore previous window position/size, or use default dimensions
    showOpts := ""
    if (w > 0 && h > 0) {
        showOpts := "x" x " y" y " w" w " h" h
    } else {
        showOpts := "w720 h500"
    }
    MainGui.Show(showOpts)
}

