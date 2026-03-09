# BUG_BACKLOG

Pending issues that are intentionally deferred. Read this file before starting new bug-fix tasks.

---

## BUG-001: `LoadAllConfigs` 重新初始化 `AllConfigs` 违反全局变量规范
- **严重度**: 🟡 MEDIUM
- **文件**: `lib/Config.ahk:50`
- **描述**: `LoadAllConfigs()` 内使用 `global AllConfigs := []` 重新赋值，违反了 AGENTS.md 中"模块仅声明 `global VarName`，不重复初始化"的规范。虽然此函数仅在启动时调用一次，当前不会导致实际问题，但如果将来被多处调用可能引发竞态风险。
- **修复方案**: 改为 `AllConfigs.Length := 0`（清空数组）或先循环 `RemoveAt` 清空，避免重新赋值全局引用。

---

## BUG-002: `SaveEnabledStates` 原子写入中 `lastConfig` 为空时丢失 `[State]` 节
- **严重度**: 🟡 MEDIUM
- **文件**: `lib/Config.ahk:320-341`
- **描述**: 当 `_state.ini` 不存在或 `[State].LastConfig` 为空时，`SaveEnabledStates` 写出的临时文件不包含 `[State]` 节。下次启动时 `IniRead(STATE_FILE, "State", "LastConfig", "")` 返回空字符串，导致无法恢复上次查看的配置。但实际上 `LoadConfigToGui` 每次切换配置时会单独写入 `LastConfig`（第 267 行），所以只有在首次启动且未切换任何配置后就发生 `SaveEnabledStates` 才会触发。
- **修复方案**: 在 `SaveEnabledStates` 中，始终保留 `[State]` 节，即使 `LastConfig` 为空也写入空值键，或改为不覆盖 `[State]` 节而只重写 `[EnabledConfigs]` 节。

---

## BUG-003: `CheckExcludeMatch` 进程名比较未做大小写归一化
- **严重度**: 🔴 HIGH
- **文件**: `lib/HotkeyEngine.ahk:52-62`
- **描述**: `CheckExcludeMatch` 直接用 `fgProc = procName` 比较前台进程名和排除列表中的进程名。AHK v2 中 `=` 运算符默认不区分大小写，**这在 AHK 中实际是安全的**。但 `CheckIncludeMatch` 使用 `WinActive("ahk_exe " procName)`，两种模式的匹配逻辑不一致：一个用 `WinActive`（匹配所有同名进程窗口），一个用 `WinGetProcessName`（只匹配前台窗口）。当前台有多窗口且进程名不同但窗口层叠时，可能产生不一致行为。
- **修复方案**: 统一 `CheckExcludeMatch` 也使用 `WinActive("ahk_exe " procName)` 逻辑，或至少将两种模式的匹配策略统一。

---

## BUG-004: 路径 C 长按连续触发无 KeyUp 停止机制
- **严重度**: 🔴 HIGH
- **文件**: `lib/HotkeyEngine.ahk:692-703`
- **描述**: 路径 A/B 的长按连续触发通过注册 `sourceKey Up` 事件来停止定时器（`HoldUpCallback`）。但路径 C 的 `PassthroughSourceHandler` 中启动长按连续定时器后，没有注册对应的 KeyUp 回调。虽然 `RepeatTimerCallback` 中有修饰键松开检测（第 633 行）和源键松开检测（第 644 行），但这两个检测都依赖轮询，且只在定时器触发时检查，存在"最后一击仍会发出"的精度问题。如果轮询检测恰好未命中（如在两次 interval 之间松键），定时器可能多发一次。
- **修复方案**: 为路径 C 注册 `*sourceKey Up` 热键（或在 `PassthroughSourceHandler` 中同步注册 Up 回调），在 KeyUp 时显式停止定时器。回退方案：当前已有的轮询检测可作为兜底，但应在文档中标注此限制。

---

## BUG-005: `CapturePolling` 中 `CaptureKeys.Length` 对比逻辑可能丢失组合键减少的情况
- **严重度**: 🟢 LOW
- **文件**: `lib/KeyCapture.ahk:233`
- **描述**: `if (totalPressed >= CaptureKeys.Length)` 使用 `>=` 来保留"最大按键组合"。但如果用户同时按下 3 键，松开 1 键再按另一键（总数仍为 3），新按的键不会被记录，因为 `totalPressed == CaptureKeys.Length` 但键组合已经变了。不过实际使用中"松开时确认"机制会在全部松开时确认，中间状态变化不影响最终结果——只要用户保持按住想要的组合即可。
- **修复方案**: 可选优化：在 `totalPressed == CaptureKeys.Length` 时也更新 `CaptureKeys`，以反映最新组合状态。优先级低，因为实际用户体验影响很小。

---

## BUG-006: 进程选择器 `ProcessPickerOpen` 双重置为 `false`
- **严重度**: 🟢 LOW
- **文件**: `lib/Utils.ahk:109, 161`
- **描述**: `OnProcessPickOK` 在函数开头（第 109 行）和结尾（第 161 行）都将 `ProcessPickerOpen` 设为 `false`。第二次赋值是冗余的，虽不影响功能但增加理解负担。
- **修复方案**: 删除第 161 行的冗余赋值。

---

## BUG-007: `OnEditMapping` DoubleClick 参数与按钮 Click 参数不一致
- **严重度**: 🟢 LOW
- **文件**: `lib/GuiEvents.ahk:305`
- **描述**: `OnEditMapping(ctrl, rowNum := 0, *)` 同时作为 ListView 的 `DoubleClick` 回调和"编辑映射"按钮的 `Click` 回调。ListView DoubleClick 传入 `(LV, rowNum)`，按钮 Click 传入 `(Btn)`。通过 `if (ctrl = MappingLV)` 区分，当前逻辑正确。但如果 DoubleClick 传入 `rowNum=0`（点击空白区域），函数直接 return，无法编辑——这是正确行为。此条仅标记为代码健壮性提醒。
- **修复方案**: 无需修改，逻辑已正确处理。可考虑添加注释说明双入口设计。

---

## BUG-008: `CanonicalizeProcessScope` 使用选择排序，大量进程时性能差
- **严重度**: 🟢 LOW
- **文件**: `lib/HotkeyEngine.ahk:275-287`
- **描述**: 手写的选择排序是 O(n²)。对于进程作用域列表通常只有几个条目，不会有实际性能问题。但如果未来支持大量进程，可能需要优化。
- **修复方案**: 可选：改用 AHK 内置 `Sort()` 函数（类似 `GetRunningProcesses` 中的用法），将数组转为换行分隔字符串后排序再拆分。优先级低。

---

## BUG-009: `RegisterPathC` 的 `*sourceKey` 通配符可能捕获意外组合
- **严重度**: 🟡 MEDIUM
- **文件**: `lib/HotkeyEngine.ahk:524`
- **描述**: `sourceHotkey := SubStr(sourceKey, 1, 1) = "*" ? sourceKey : "*" sourceKey` 为源键添加 `*` 前缀（忽略修饰键状态）。这意味着即使按住其他修饰键（如 Ctrl+sourceKey），也会触发此热键。在 `PassthroughSourceHandler` 中虽然会检查对应修饰键是否按下，但如果没有匹配到任何修饰键，会发送原始 sourceKey（第 711 行），此时会丢失用户实际按下的其他修饰键组合。
- **修复方案**: 在"没有任何修饰键按住"的 fallback 分支中，检测当前实际按下的修饰键并一起发送，或使用 `{Blind}` 模式发送 sourceKey。

---

## BUG-010: 路径 B 修饰键恢复 `RestoreModKeyCallback` 无条件发送修饰键
- **严重度**: 🟡 MEDIUM
- **文件**: `lib/HotkeyEngine.ahk:667-669`
- **描述**: 路径 B 中为修饰键单独注册了恢复回调 `RestoreModKeyCallback`，在用户单独按下修饰键时发送修饰键自身。但 `KeyToSendFormat` 对于鼠标按键（如 `MButton`、`XButton1`）会生成 `{MButton}` 等格式，`Send` 对鼠标键的行为是模拟鼠标点击。这意味着如果用户将鼠标键设为修饰键并单独按下，会触发一次模拟鼠标点击，这可能不是预期行为。
- **修复方案**: 对鼠标按键跳过恢复回调，或在恢复回调中区分键盘键和鼠标键。

---

## BUG-011: `SaveConfig` 覆盖写入时不清理旧的多余 Mapping 节
- **严重度**: 🔴 HIGH
- **文件**: `lib/Config.ahk:270-317`
- **描述**: `SaveConfig` 使用原子写入（先写 .tmp 再 `FileMove` 覆盖）。由于是完整重写临时文件，旧文件的多余节会被自然覆盖。**当前实现是正确的**——原子写入确保了旧数据不会残留。此条标记为已验证无问题。
- **修复方案**: 无需修改。

---

## BUG-012: `EnableAutoStart` 非编译模式下路径含空格时注册表值格式问题
- **严重度**: 🟢 LOW
- **文件**: `lib/Utils.ahk:216`
- **描述**: `EnableAutoStart` 在非编译模式下生成 `'"' A_AhkPath '" "' A_ScriptFullPath '"'`。如果 AHK 安装路径或脚本路径包含空格，双引号包裹可正确处理。但如果路径包含 `"` 字符本身（极其罕见），会导致注册表值格式错误。
- **修复方案**: 路径包含双引号的情况极其罕见，可忽略。优先级极低。

---

## BUG-013: 路径 C `PassthroughSourceHandler` fallback 中 `Send` 可能触发自身热键
- **严重度**: 🟡 MEDIUM
- **文件**: `lib/HotkeyEngine.ahk:708-711`
- **描述**: 当路径 C 注册了 `*sourceKey`，且没有修饰键按下时，fallback 会 `Send(KeyToSendFormat(sourceKey))`。由于热键本身拦截了 sourceKey 的物理输入，`Send` 发送的是虚拟输入，可能再次触发同一热键，导致无限递归。AHK 的 `#InputLevel` 默认行为应该能防止这种递归（Send 发送的事件在更低层级），但如果配置了多层路径 C 映射，可能存在风险。
- **修复方案**: 在 fallback Send 前使用 `SendLevel 0` 或 `Send("{Blind}" ...)` 确保不触发自身。或使用 `#InputLevel` 显式设置。

---

## BUG-014: 模态窗口 `OnEvent("Close")` 的闭包可能保持对 GUI 对象的引用
- **严重度**: 🟢 LOW
- **文件**: `lib/GuiMain.ahk:133`
- **描述**: `modalGui.OnEvent("Close", (*) => DestroyModalGui(modalGui))` 中的闭包捕获了 `modalGui` 引用。`DestroyModalGui` 调用 `modalGui.Destroy()` 后，闭包中的引用仍存在，但 AHK 的 GC 应能处理已销毁的 GUI 对象。不会导致实际问题，但可能延迟 GC。
- **修复方案**: 可选：使用弱引用模式或确保闭包中的引用在 Destroy 后被清除。优先级极低。

---

## OPT-001: 全量热键重载可优化为增量重载
- **类型**: ⚡ 优化
- **文件**: `lib/HotkeyEngine.ahk:140-142`
- **描述**: `ReloadConfigHotkeys(configName)` 当前直接调用 `ReloadAllHotkeys()`，即使只修改了一个配置也需要卸载并重新注册所有配置的热键。对于少量配置（<10）影响不大，但如果配置数量增多或映射条目很多，每次编辑映射都会触发全量重载。
- **修复方案**: 实现增量重载——仅卸载并重新注册被修改配置的热键。需要注意路径 C 的修饰键状态是跨配置共享的，需要小心处理。复杂度较高，可在性能成为瓶颈时实施。

---

## OPT-002: `GetRunningProcesses` 每次打开进程选择器都全量扫描
- **类型**: ⚡ 优化
- **文件**: `lib/Utils.ahk:165-201`
- **描述**: 每次打开进程选择器都遍历所有窗口获取进程列表。如果系统窗口很多（>100），可能有可感知的延迟。
- **修复方案**: 可选：缓存进程列表，设定 TTL（如 5 秒），在 TTL 内复用缓存。优先级低。

---

## OPT-003: `DetectHotkeyConflicts` 使用 O(n²) 同组比较
- **类型**: ⚡ 优化
- **文件**: `lib/HotkeyEngine.ahk:212-234`
- **描述**: 对同一热键字符串下的所有条目做两两比较。在极端情况下（大量配置映射相同热键），性能可能不理想。但实际使用中同一热键出现在多个配置中的情况很少。
- **修复方案**: 当前实现足够。如果未来需要，可以用 Map 做去重优化。优先级极低。

---

## OPT-004: 按键捕获轮询可考虑使用 `Input` 命令替代
- **类型**: ⚡ 优化
- **文件**: `lib/KeyCapture.ahk`
- **描述**: 当前使用 30ms 轮询 `GetKeyState` 检测按键。AHK v2 的 `InputHook` 提供了事件驱动的按键检测，可以减少 CPU 占用并提高响应精度。但 `InputHook` 对鼠标按键支持有限，且当前的"松开时确认"机制需要同时追踪多键状态，`InputHook` 可能不完全适用。
- **修复方案**: 可部分使用 `InputHook` 替代键盘轮询，鼠标部分保留 `OnMessage`。改动较大，需要充分测试。优先级中等。

---

## OPT-005: `RefreshConfigList` 每次调用 `GetConfigList()` 重新扫描文件系统
- **类型**: ⚡ 优化
- **文件**: `lib/Config.ahk:146-180`
- **描述**: `RefreshConfigList` 通过 `GetConfigList()` 扫描 `configs/*.ini` 获取配置列表，而不是直接使用已加载的 `AllConfigs`。这导致每次刷新都有一次文件系统 IO。由于配置目录中文件数量通常很少，影响微乎其微。
- **修复方案**: 可选：从 `AllConfigs` 提取名称列表而非重新扫描文件系统。优先级极低。
