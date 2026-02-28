; ============================================================================
; AHKeyMap - AHKv2 按键映射工具
; 支持多配置管理、多进程绑定、按键捕获、组合键映射、长按连续触发
; 支持自定义修饰键（含鼠标按键）、滚轮映射、状态追踪式组合键
; 支持多配置同时生效、三态进程作用域（全局/仅指定/排除指定）
; ============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

;@Ahk2Exe-SetName AHKeyMap
;@Ahk2Exe-SetDescription AHKeyMap - 按键映射工具
;@Ahk2Exe-SetVersion 2.3.3
;@Ahk2Exe-SetCopyright Copyright (c) 2026
;@Ahk2Exe-SetMainIcon icon.ico

; ============================================================================
; 全局变量（所有模块共享）
; ============================================================================
global APP_NAME := "AHKeyMap"
global APP_VERSION := "2.3.3"
global SCRIPT_DIR := A_ScriptDir
global CONFIG_DIR := SCRIPT_DIR "\configs"
global STATE_FILE := CONFIG_DIR "\_state.ini"
global REG_RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
global REG_VALUE_NAME := "AHKeyMap"

; 定时器与默认值常量
global CAPTURE_START_DELAY := 200       ; 按键捕获启动延迟（ms）
global CAPTURE_POLL_INTERVAL := 30      ; 按键捕获轮询间隔（ms）
global CONTEXT_MENU_DISMISS_DELAY := 10 ; 右键菜单抑制延迟（ms）
global DEFAULT_REPEAT_DELAY := 300      ; 长按连续触发默认延迟（ms）
global DEFAULT_REPEAT_INTERVAL := 50    ; 长按连续触发默认间隔（ms）

; 配置相关全局变量
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

; GUI 控件相关全局变量
global MainGui := ""
global ConfigDDL := ""
global EnabledCB := ""
global ProcessText := ""
global MappingLV := ""
global StatusText := ""
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

; 热键引擎相关全局变量
global ActiveHotkeys := []
global HoldTimers := Map()
global ComboFiredState := Map()
global PassthroughModKeys := Map()
global InterceptModKeys := Map()
global PassthroughHandlers := Map()
global PassthroughSourceRegistered := Map()
global AllProcessCheckers := []
global HotkeyConflicts := []
global HotkeyRegErrors := []

; 按键捕获相关全局变量
global IsCapturing := false
global CaptureTarget := ""
global CaptureGui := ""
global CaptureDisplayText := ""
global CaptureTimer := ""
global CaptureKeys := []
global CaptureHadKeys := false
global CaptureMouseKeys := Map()

; 进程选择器相关全局变量
global ProcessPickerOpen := false

; ============================================================================
; Include 模块
; ============================================================================
#Include "lib/Config.ahk"
#Include "lib/Utils.ahk"
#Include "lib/HotkeyEngine.ahk"
#Include "lib/KeyCapture.ahk"
#Include "lib/GuiMain.ahk"
#Include "lib/MappingEditor.ahk"
#Include "lib/GuiEvents.ahk"


; ============================================================================
; 托盘和窗口事件
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

; 托盘菜单切换自启
OnTrayAutoStartToggle(*) {
    if IsAutoStartEnabled() {
        DisableAutoStart()
        A_TrayMenu.Uncheck("开机自启")
    } else {
        EnableAutoStart()
        A_TrayMenu.Check("开机自启")
    }
}

OnRunAsAdmin(*) {
    if A_IsAdmin {
        MsgBox("当前已经是管理员模式", APP_NAME, "Icon!")
        return
    }
    try {
        Run('*RunAs "' A_ScriptFullPath '"')
        ExitApp()
    } catch as e {
        MsgBox("提权失败，可能被用户取消了`n" e.Message, APP_NAME, "Icon!")
    }
}

; ============================================================================
; 启动入口
; ============================================================================
StartApp()

StartApp() {
    ; 确保配置目录存在
    if !DirExist(CONFIG_DIR)
        DirCreate(CONFIG_DIR)

    ; 加载上次使用的配置（用于 GUI 显示）
    lastConfig := ""
    if FileExist(STATE_FILE)
        lastConfig := IniRead(STATE_FILE, "State", "LastConfig", "")

    ; 构建主界面
    BuildMainGui()

    ; 加载所有配置到 AllConfigs 并注册已启用配置的热键
    LoadAllConfigs()

    ; 启动时同步启用状态，清理 _state.ini 中的历史残留键
    SaveEnabledStates()

    ; 刷新配置下拉列表（仅 GUI 显示）
    RefreshConfigList(lastConfig)

    ; 注册所有已启用配置的热键
    ReloadAllHotkeys()

    ; 显示主窗口
    MainGui.Show("w720 h500")
}
