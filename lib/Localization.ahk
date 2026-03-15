; ============================================================================
; AHKeyMap - Localization module
; Lightweight ZH/EN language packs and L(key, args*) helper
; ============================================================================

; Declare globals owned/initialized in AHKeyMap.ahk
global CurrentLangCode

; Return language pack Map for given lang code, falling back to en-US
GetLangPack(langCode) {
    static packs := Map(
        "en-US", BuildEnPack(),
        "zh-CN", BuildZhPack()
    )
    if !packs.Has(langCode)
        langCode := "en-US"
    return packs[langCode]
}

; Main localization helper
; L("Key") -> localized string
; L("Key", arg1, arg2, ...) -> Format(template, args*)
L(key, args*) {
    global CurrentLangCode
    pack := GetLangPack(CurrentLangCode)
    text := ""

    if pack.Has(key) {
        text := pack[key]
    } else {
        ; Fallback to en-US, then printable key name
        fallback := GetLangPack("en-US")
        text := fallback.Has(key) ? fallback[key] : "[" key "]"
    }

    return args.Length ? Format(text, args*) : text
}

; Detect default UI language.
; NOTE: The app now defaults to English when there is no persisted UILanguage,
; so this helper is kept only for potential future use.
DetectDefaultLanguage() {
    return "en-US"
}

; --------------------------------------------------------------------------
; Language packs
; --------------------------------------------------------------------------

BuildEnPack() {
    pack := Map()

    ; ---- General ----
    pack["General.LanguageChangeRequiresRestart"] := "Language changed. Please restart AHKeyMap to apply the new UI language."
    pack["General.AlreadyAdmin"] := "Already running as administrator."
    pack["General.ElevateFailed"] := "Failed to elevate. It may have been cancelled by the user.`n{1}"

    ; ---- Main window / GuiMain ----
    pack["GuiMain.Title"] := "{1} v{2}"
    pack["GuiMain.Title.AdminSuffix"] := " [Admin]"
    pack["GuiMain.ConfigLabel"] := "Config:"
    pack["GuiMain.EnableCheckbox"] := "On"
    pack["GuiMain.NewConfigButton"] := "New"
    pack["GuiMain.CopyConfigButton"] := "Copy"
    pack["GuiMain.DeleteConfigButton"] := "Delete"
    pack["GuiMain.ScopeButton"] := "Scope"
    pack["GuiMain.ScopeNone"] := "Scope: No config"

    pack["GuiMain.Mapping.ColIndex"] := "#"
    pack["GuiMain.Mapping.ColModifier"] := "Modifier"
    pack["GuiMain.Mapping.ColSource"] := "Source"
    pack["GuiMain.Mapping.ColTarget"] := "Target"
    pack["GuiMain.Mapping.ColHoldRepeat"] := "Repeat"
    pack["GuiMain.Mapping.ColModMode"] := "Modifier mode"
    pack["GuiMain.Mapping.ColDelay"] := "Delay (ms)"
    pack["GuiMain.Mapping.ColInterval"] := "Interval (ms)"

    pack["GuiMain.AddMappingButton"] := "Add"
    pack["GuiMain.EditMappingButton"] := "Edit"
    pack["GuiMain.CopyMappingButton"] := "Copy"
    pack["GuiMain.DeleteMappingButton"] := "Delete"
    pack["GuiMain.RunAsAdminButton"] := "Restart as admin"

    pack["GuiMain.Status.EnabledSummary"] := "Enabled {1}/{2}"
    pack["GuiMain.Status.ConflictSummary"] := "⚠ {1} hotkey conflicts"
    pack["GuiMain.Status.RegErrorSummary"] := "⚠ {1} hotkey registration errors"
    pack["GuiMain.Status.DetailLink"] := "Details"
    pack["GuiMain.Status.DetailTooltip"] := "Click to view conflicts and registration errors"

    pack["GuiMain.Status.ConflictsHeader"] := "Hotkey conflicts:`n"
    pack["GuiMain.Status.ConflictItem"] := "  {1} ({2} / {3})`n"
    pack["GuiMain.Status.RegErrorsHeader"] := "Registration errors:`n"
    pack["GuiMain.Status.RegErrorItem"] := "  {1}`n"

    ; Tray
    pack["Tray.ShowMainWindow"] := "Show main window"
    pack["Tray.AutoStart"] := "Run at startup"
    pack["Tray.RunAsAdmin"] := "Restart as admin"
    pack["Tray.Exit"] := "Exit"
    pack["Tray.LanguageMenu"] := "Language"
    pack["Tray.Language.En"] := "English"
    pack["Tray.Language.ZhHans"] := "Simplified Chinese"

    ; ---- Config / scope display (Config.ahk) ----
    pack["Config.Scope.Global"] := "Scope: Global"
    pack["Config.Scope.None"] := "Scope: No config"
    pack["Config.Scope.Include.Single"] := "Scope: Only {1}"
    pack["Config.Scope.Include.Multi"] := "Scope: Only {1} and {2} more"
    pack["Config.Scope.Exclude.Single"] := "Scope: Exclude {1}"
    pack["Config.Scope.Exclude.Multi"] := "Scope: Exclude {1} and {2} more"

    pack["Config.Status.EnabledSummary"] := "Enabled {1}/{2}"
    pack["Config.Status.ConflictSuffix"] := "  ⚠ {1} hotkey conflicts"
    pack["Config.Status.RegErrorSuffix"] := "  ⚠ {1} hotkey registration errors"

    pack["Config.Refresh.NoConfigScope"] := "Scope: No config"
    pack["Config.SaveError.WriteTemp"] := "Failed to save config: {1}`nFile: {2}"
    pack["Config.SaveError.Replace"] := "Failed to save config (replace stage): {1}`nFile: {2}"
    pack["Config.SaveEnabledStatesError"] := "Failed to save enabled states: {1}"

    pack["Config.Mapping.HoldYes"] := "Yes"
    pack["Config.Mapping.HoldNo"] := "No"
    pack["Config.Mapping.ModMode.Pass"] := "Pass-through"
    pack["Config.Mapping.ModMode.Block"] := "Intercept"

    ; ---- GuiEvents: config dialogs & errors ----
    pack["GuiEvents.NewConfig.Title"] := "New config"
    pack["GuiEvents.NewConfig.NameLabel"] := "Config name:"
    pack["GuiEvents.NewConfig.ScopeGroup"] := "Scope"
    pack["GuiEvents.NewConfig.ScopeGlobal"] := "Global"
    pack["GuiEvents.NewConfig.ScopeInclude"] := "Only for listed processes"
    pack["GuiEvents.NewConfig.ScopeExclude"] := "Exclude listed processes"
    pack["GuiEvents.NewConfig.ProcessListLabel"] := "Process list:"
    pack["GuiEvents.NewConfig.ProcessListHint"] := "(one process name per line)"
    pack["GuiEvents.Common.ProcessPickButton"] := "Pick"
    pack["GuiEvents.Common.OkButton"] := "OK"
    pack["GuiEvents.Common.CancelButton"] := "Cancel"

    pack["GuiEvents.CopyConfig.Title"] := "Copy config"
    pack["GuiEvents.CopyConfig.NewNameLabel"] := "New name:"

    pack["GuiEvents.ChangeScope.Title"] := "Edit scope"
    pack["GuiEvents.ChangeScope.ModeGroup"] := "Scope mode"

    pack["GuiEvents.Error.NameRequired"] := "Please enter a config name."
    pack["GuiEvents.Error.NameInvalidChars"] := "Config name cannot contain these characters: \\ / : * ? < > | = [ ] and double quotes"
    pack["GuiEvents.Error.ConfigExists"] := "Config '{1}' already exists."
    pack["GuiEvents.Error.NoConfigSelected"] := "No config selected."
    pack["GuiEvents.Confirm.DeleteConfig"] := "Are you sure you want to delete config '{1}'?"

    pack["GuiEvents.Error.SelectOrCreateConfig"] := "Please select or create a config first."
    pack["GuiEvents.Error.SelectMappingFirst"] := "Please select a mapping first."
    pack["GuiEvents.Confirm.DeleteMapping"] := "Are you sure you want to delete this mapping?"

    ; ---- Mapping editor ----
    pack["MappingEditor.Title.Edit"] := "Edit mapping"
    pack["MappingEditor.Title.New"] := "New mapping"

    pack["MappingEditor.ModifierLabel"] := "Modifier:"
    pack["MappingEditor.SourceLabel"] := "Source key:"
    pack["MappingEditor.TargetLabel"] := "Target key:"
    pack["MappingEditor.CaptureButton"] := "Capture"
    pack["MappingEditor.ClearButton"] := "Clear"

    pack["MappingEditor.HoldRepeatLabel"] := "Repeated while held"
    pack["MappingEditor.DelayLabel"] := "Delay (ms):"
    pack["MappingEditor.IntervalLabel"] := "Interval (ms):"
    pack["MappingEditor.PassthroughLabel"] := "Keep modifier's original behavior (gestures/drag, etc.)"
    pack["MappingEditor.OkButton"] := "OK"
    pack["MappingEditor.CancelButton"] := "Cancel"

    pack["MappingEditor.Error.SourceRequired"] := "Please set a source key."
    pack["MappingEditor.Error.TargetRequired"] := "Please set a target key."

    ; ---- Utils: process picker ----
    pack["Utils.ProcessPicker.Title"] := "Select process"
    pack["Utils.ProcessPicker.ManualLabel"] := "Manual input:"
    pack["Utils.ProcessPicker.ListHint"] := "Or select from the list below (multi-select supported):"

    ; ---- KeyCapture: key capture window ----
    pack["KeyCapture.Title"] := "Key capture"
    pack["KeyCapture.MainPrompt"] := "Press the key combination..."
    pack["KeyCapture.SubPrompt"] := "Release all keys to confirm, press Esc to cancel"

    return pack
}

BuildZhPack() {
    pack := Map()

    ; ---- General ----
    pack["General.LanguageChangeRequiresRestart"] := "语言已更改，请重启 AHKeyMap 以应用新的界面语言。"
    pack["General.AlreadyAdmin"] := "当前已经是管理员模式"
    pack["General.ElevateFailed"] := "提权失败，可能被用户取消了`n{1}"

    ; ---- Main window / GuiMain ----
    pack["GuiMain.Title"] := "{1} v{2}"
    pack["GuiMain.Title.AdminSuffix"] := " [管理员]"
    pack["GuiMain.ConfigLabel"] := "配置:"
    pack["GuiMain.EnableCheckbox"] := "启用"
    pack["GuiMain.NewConfigButton"] := "新建"
    pack["GuiMain.CopyConfigButton"] := "复制"
    pack["GuiMain.DeleteConfigButton"] := "删除"
    pack["GuiMain.ScopeButton"] := "作用域"
    pack["GuiMain.ScopeNone"] := "作用域: 无配置"

    pack["GuiMain.Mapping.ColIndex"] := "序号"
    pack["GuiMain.Mapping.ColModifier"] := "修饰键"
    pack["GuiMain.Mapping.ColSource"] := "源按键"
    pack["GuiMain.Mapping.ColTarget"] := "映射目标"
    pack["GuiMain.Mapping.ColHoldRepeat"] := "长按连续"
    pack["GuiMain.Mapping.ColModMode"] := "修饰键模式"
    pack["GuiMain.Mapping.ColDelay"] := "触发延迟(ms)"
    pack["GuiMain.Mapping.ColInterval"] := "触发间隔(ms)"

    pack["GuiMain.AddMappingButton"] := "新增映射"
    pack["GuiMain.EditMappingButton"] := "编辑映射"
    pack["GuiMain.CopyMappingButton"] := "复制映射"
    pack["GuiMain.DeleteMappingButton"] := "删除映射"
    pack["GuiMain.RunAsAdminButton"] := "以管理员重启"

    pack["GuiMain.Status.EnabledSummary"] := "已启用 {1}/{2} 个配置"
    pack["GuiMain.Status.ConflictSummary"] := "  ⚠ {1} 个热键冲突"
    pack["GuiMain.Status.RegErrorSummary"] := "  ⚠ {1} 个热键注册失败"
    pack["GuiMain.Status.DetailLink"] := "查看详情"
    pack["GuiMain.Status.DetailTooltip"] := "点击查看冲突与注册失败详情"

    pack["GuiMain.Status.ConflictsHeader"] := "热键冲突：`n"
    pack["GuiMain.Status.ConflictItem"] := "  {1}（{2} / {3}）`n"
    pack["GuiMain.Status.RegErrorsHeader"] := "注册失败：`n"
    pack["GuiMain.Status.RegErrorItem"] := "  {1}`n"

    ; Tray
    pack["Tray.ShowMainWindow"] := "显示主窗口"
    pack["Tray.AutoStart"] := "开机自启"
    pack["Tray.RunAsAdmin"] := "以管理员身份重启"
    pack["Tray.Exit"] := "退出"
    pack["Tray.LanguageMenu"] := "语言"
    pack["Tray.Language.En"] := "English"
    pack["Tray.Language.ZhHans"] := "简体中文"

    ; ---- Config / scope display (Config.ahk) ----
    pack["Config.Scope.Global"] := "作用域: 全局"
    pack["Config.Scope.None"] := "作用域: 无配置"
    pack["Config.Scope.Include.Single"] := "作用域: 仅 {1}"
    pack["Config.Scope.Include.Multi"] := "作用域: 仅 {1} 等{2}个"
    pack["Config.Scope.Exclude.Single"] := "作用域: 排除 {1}"
    pack["Config.Scope.Exclude.Multi"] := "作用域: 排除 {1} 等{2}个"

    pack["Config.Status.EnabledSummary"] := "已启用 {1}/{2} 个配置"
    pack["Config.Status.ConflictSuffix"] := "  ⚠ {1} 个热键冲突"
    pack["Config.Status.RegErrorSuffix"] := "  ⚠ {1} 个热键注册失败"

    pack["Config.Refresh.NoConfigScope"] := "作用域: 无配置"
    pack["Config.SaveError.WriteTemp"] := "保存配置失败：{1}`n文件：{2}"
    pack["Config.SaveError.Replace"] := "保存配置失败（替换阶段）：{1}`n文件：{2}"
    pack["Config.SaveEnabledStatesError"] := "保存启用状态失败：{1}"

    pack["Config.Mapping.HoldYes"] := "是"
    pack["Config.Mapping.HoldNo"] := "否"
    pack["Config.Mapping.ModMode.Pass"] := "保留"
    pack["Config.Mapping.ModMode.Block"] := "拦截"

    ; ---- GuiEvents: config dialogs & errors ----
    pack["GuiEvents.NewConfig.Title"] := "新建配置"
    pack["GuiEvents.NewConfig.NameLabel"] := "配置名称:"
    pack["GuiEvents.NewConfig.ScopeGroup"] := "作用域"
    pack["GuiEvents.NewConfig.ScopeGlobal"] := "全局生效"
    pack["GuiEvents.NewConfig.ScopeInclude"] := "仅指定进程生效"
    pack["GuiEvents.NewConfig.ScopeExclude"] := "排除指定进程"
    pack["GuiEvents.NewConfig.ProcessListLabel"] := "进程列表:"
    pack["GuiEvents.NewConfig.ProcessListHint"] := "（每行一个进程名）"
    pack["GuiEvents.Common.ProcessPickButton"] := "选择"
    pack["GuiEvents.Common.OkButton"] := "确定"
    pack["GuiEvents.Common.CancelButton"] := "取消"

    pack["GuiEvents.CopyConfig.Title"] := "复制配置"
    pack["GuiEvents.CopyConfig.NewNameLabel"] := "新名称:"

    pack["GuiEvents.ChangeScope.Title"] := "修改作用域"
    pack["GuiEvents.ChangeScope.ModeGroup"] := "作用域模式"

    pack["GuiEvents.Error.NameRequired"] := "请输入配置名称"
    pack["GuiEvents.Error.NameInvalidChars"] := "配置名称不能包含以下字符：\\ / : * ? < > | = [ ] 以及双引号"
    pack["GuiEvents.Error.ConfigExists"] := "配置 '{1}' 已存在"
    pack["GuiEvents.Error.NoConfigSelected"] := "没有选中的配置"
    pack["GuiEvents.Confirm.DeleteConfig"] := "确定要删除配置 '{1}' 吗？"

    pack["GuiEvents.Error.SelectOrCreateConfig"] := "请先选择或新建一个配置"
    pack["GuiEvents.Error.SelectMappingFirst"] := "请先选中一个映射"
    pack["GuiEvents.Confirm.DeleteMapping"] := "确定要删除这个映射吗？"

    ; ---- Mapping editor ----
    pack["MappingEditor.Title.Edit"] := "编辑映射"
    pack["MappingEditor.Title.New"] := "新增映射"

    pack["MappingEditor.ModifierLabel"] := "修饰键:"
    pack["MappingEditor.SourceLabel"] := "源按键:"
    pack["MappingEditor.TargetLabel"] := "映射目标:"
    pack["MappingEditor.CaptureButton"] := "捕获"
    pack["MappingEditor.ClearButton"] := "清除"

    pack["MappingEditor.HoldRepeatLabel"] := "长按连续触发"
    pack["MappingEditor.DelayLabel"] := "触发延迟(ms):"
    pack["MappingEditor.IntervalLabel"] := "触发间隔(ms):"
    pack["MappingEditor.PassthroughLabel"] := "保留修饰键原始功能（手势/拖拽等不受影响）"
    pack["MappingEditor.OkButton"] := "确定"
    pack["MappingEditor.CancelButton"] := "取消"

    pack["MappingEditor.Error.SourceRequired"] := "请设置源按键"
    pack["MappingEditor.Error.TargetRequired"] := "请设置映射目标"

    ; ---- Utils: process picker ----
    pack["Utils.ProcessPicker.Title"] := "选择进程"
    pack["Utils.ProcessPicker.ManualLabel"] := "手动输入:"
    pack["Utils.ProcessPicker.ListHint"] := "或从下方列表选择（可多选）:"

    ; ---- KeyCapture: key capture window ----
    pack["KeyCapture.Title"] := "按键捕获"
    pack["KeyCapture.MainPrompt"] := "请按下按键组合..."
    pack["KeyCapture.SubPrompt"] := "松开所有键后自动确认，按 Esc 取消"

    return pack
}
