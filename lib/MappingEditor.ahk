; ============================================================================
; AHKeyMap - 映射编辑弹窗模块
; 负责映射编辑窗口的构建和事件处理
; ============================================================================

; 声明跨文件使用的全局变量
global APP_NAME
global Mappings
global MainGui
global DEFAULT_REPEAT_DELAY
global DEFAULT_REPEAT_INTERVAL

; GUI 控件引用（导出到 KeyCapture 模块）
global EditModifierEdit
global EditSourceEdit
global EditTargetEdit
global EditHoldRepeatCB
global EditDelayEdit
global EditIntervalEdit
global EditPassthroughCB
global EditingIndex

; ============================================================================
; 映射编辑弹窗
; ============================================================================

ShowEditMappingGui() {
    global EditGui := CreateModalGui(EditingIndex > 0 ? "编辑映射" : "新增映射")
    EditGui.SetFont("s9", "Microsoft YaHei UI")

    ; 修饰键（新增行）
    EditGui.AddText("x10 y10 w70 h23 +0x200", "修饰键:")
    global EditModifierEdit := EditGui.AddEdit("x80 y10 w180 h23 vModifierKey ReadOnly")
    EditGui.AddButton("x265 y9 w65 h25", "捕获").OnEvent("Click", OnCaptureModifier)
    EditGui.AddButton("x335 y9 w50 h25", "清除").OnEvent("Click", OnClearModifier)

    ; 源按键
    EditGui.AddText("x10 y45 w70 h23 +0x200", "源按键:")
    global EditSourceEdit := EditGui.AddEdit("x80 y45 w180 h23 vSourceKey ReadOnly")
    EditGui.AddButton("x265 y44 w65 h25", "捕获").OnEvent("Click", OnCaptureSource)

    ; 映射目标
    EditGui.AddText("x10 y80 w70 h23 +0x200", "映射目标:")
    global EditTargetEdit := EditGui.AddEdit("x80 y80 w180 h23 vTargetKey ReadOnly")
    EditGui.AddButton("x265 y79 w65 h25", "捕获").OnEvent("Click", OnCaptureTarget)

    ; 长按连续触发
    global EditHoldRepeatCB := EditGui.AddCheckbox("x10 y115 w150 h23 vHoldRepeat", "长按连续触发")
    EditHoldRepeatCB.OnEvent("Click", OnHoldRepeatToggle)

    ; 触发延迟
    EditGui.AddText("x10 y145 w100 h23 +0x200", "触发延迟(ms):")
    global EditDelayEdit := EditGui.AddEdit("x110 y145 w80 h23 vRepeatDelay Number")
    EditDelayEdit.Value := String(DEFAULT_REPEAT_DELAY)

    ; 触发间隔
    EditGui.AddText("x200 y145 w100 h23 +0x200", "触发间隔(ms):")
    global EditIntervalEdit := EditGui.AddEdit("x300 y145 w80 h23 vRepeatInterval Number")
    EditIntervalEdit.Value := String(DEFAULT_REPEAT_INTERVAL)

    ; 保留修饰键原始功能
    global EditPassthroughCB := EditGui.AddCheckbox("x10 y175 w370 h23 vPassthroughMod", "保留修饰键原始功能（手势/拖拽等不受影响）")

    ; 如果是编辑模式，填入现有数据
    if (EditingIndex > 0 && EditingIndex <= Mappings.Length) {
        m := Mappings[EditingIndex]
        EditModifierEdit.Value := KeyToDisplay(m["ModifierKey"])
        EditModifierEdit.ahkKey := m["ModifierKey"]
        EditSourceEdit.Value := KeyToDisplay(m["SourceKey"])
        EditSourceEdit.ahkKey := m["SourceKey"]
        EditTargetEdit.Value := KeyToDisplay(m["TargetKey"])
        EditTargetEdit.ahkKey := m["TargetKey"]
        EditHoldRepeatCB.Value := m["HoldRepeat"]
        EditDelayEdit.Value := m["RepeatDelay"]
        EditIntervalEdit.Value := m["RepeatInterval"]
        EditPassthroughCB.Value := m["PassthroughMod"]
    } else {
        EditModifierEdit.ahkKey := ""
        EditSourceEdit.ahkKey := ""
        EditTargetEdit.ahkKey := ""
    }

    ; 根据状态控制控件可用性
    OnHoldRepeatToggle(EditHoldRepeatCB, "")
    UpdatePassthroughState()

    ; 按钮
    EditGui.AddButton("x100 y210 w80 h28", "确定").OnEvent("Click", OnEditMappingOK)
    EditGui.AddButton("x190 y210 w80 h28", "取消").OnEvent("Click", (*) => DestroyModalGui(EditGui))
    EditGui.Show("w395 h250")
}

OnClearModifier(*) {
    EditModifierEdit.Value := ""
    EditModifierEdit.ahkKey := ""
    UpdatePassthroughState()
}

OnHoldRepeatToggle(ctrl, *) {
    isEnabled := ctrl.Value
    EditDelayEdit.Enabled := isEnabled
    EditIntervalEdit.Enabled := isEnabled
}

OnEditMappingOK(*) {
    modifierAhk := EditModifierEdit.ahkKey
    sourceAhk := EditSourceEdit.ahkKey
    targetAhk := EditTargetEdit.ahkKey

    if (sourceAhk = "") {
        MsgBox("请设置源按键", APP_NAME, "Icon!")
        return
    }
    if (targetAhk = "") {
        MsgBox("请设置映射目标", APP_NAME, "Icon!")
        return
    }

    mapping := Map()
    mapping["ModifierKey"] := modifierAhk
    mapping["SourceKey"] := sourceAhk
    mapping["TargetKey"] := targetAhk
    mapping["HoldRepeat"] := EditHoldRepeatCB.Value ? 1 : 0
    mapping["RepeatDelay"] := EditDelayEdit.Value != "" ? Integer(EditDelayEdit.Value) : DEFAULT_REPEAT_DELAY
    mapping["RepeatInterval"] := EditIntervalEdit.Value != "" ? Integer(EditIntervalEdit.Value) : DEFAULT_REPEAT_INTERVAL
    mapping["PassthroughMod"] := EditPassthroughCB.Value ? 1 : 0

    if (EditingIndex > 0 && EditingIndex <= Mappings.Length) {
        Mappings[EditingIndex] := mapping
    } else {
        Mappings.Push(mapping)
    }

    SaveConfig()
    RefreshMappingLV()
    ReloadAllHotkeys()
    DestroyModalGui(EditGui)
}
