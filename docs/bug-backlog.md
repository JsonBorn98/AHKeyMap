# BUG_BACKLOG

Pending issues that are intentionally deferred. Read this file before starting new bug-fix tasks.

## 状态说明
- `待修`: 已通过代码阅读或现象观察确认，后续可直接进入修复。
- `待验证`: 有风险点，但还缺少稳定复现或运行时证据。
- `已确认非问题`: 已核实当前实现可接受，保留记录仅用于避免重复讨论。
- `已合并`: 该编号已并入另一条，后续以目标条目为准。
- `已修复`: 已在代码中落地并完成验证，保留记录仅用于追溯。

## 留档字段
- `严重度`: High / Medium / Low
- `置信度`: 高 / 中 / 低
- `验证方式`: 修复后至少应执行的手工验证路径

---

## BUG-001: `LoadAllConfigs` 重新赋值 `AllConfigs`
- 状态: 已修复
- 严重度: Low
- 置信度: 高
- 文件: `src/core/Config.ahk:51-58`
- 影响范围: 配置加载链路、全局变量引用一致性
- 复现条件: 旧实现会在 `LoadAllConfigs()` 中替换 `AllConfigs` 数组对象。
- 当前观察: `LoadAllConfigs()` 已改为 `AllConfigs.Length := 0` 后原地重建，不再替换全局数组对象；`tests/integration/config_io.test.ahk` 已覆盖“复用同一数组对象”的回归场景。
- 修复方向: 无需继续处理。
- 验证方式: `AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\integration\config_io.test.ahk`；并手工确认新建、复制配置后的列表刷新与热键重载正常。

---

## BUG-002: `SaveEnabledStates` 在边界场景下可能写出不完整的 `[State]`
- 状态: 已修复
- 严重度: Low
- 置信度: 中
- 文件: `src/core/Config.ahk:340-364`
- 影响范围: `_state.ini` 的 `LastConfig` 持久化
- 复现条件: 旧实现只在 `lastConfig != ""` 时回写 `[State]`，边界场景下可能丢失状态节。
- 当前观察: `SaveEnabledStates()` 现会稳定写出 `[State].LastConfig` 与 `[State].UILanguage`，空 `LastConfig` 也不会跳过状态节；`tests/integration/config_io.test.ahk` 已覆盖状态元数据保留场景。
- 修复方向: 无需继续处理。
- 验证方式: `AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\integration\config_io.test.ahk`；必要时删除 `configs\_state.ini` 后手工启动应用复查恢复逻辑。

---

## BUG-003: include / exclude 进程匹配策略不一致
- 状态: 已修复
- 严重度: Medium
- 置信度: 中
- 文件: `src/core/HotkeyEngine.ahk:27-76`
- 影响范围: 进程作用域判断、冲突排查一致性
- 复现条件: 旧实现曾对 include / exclude 使用不同的前台进程匹配基线。
- 当前观察: `CheckIncludeMatch()` 与 `CheckExcludeMatch()` 现都基于 `GetForegroundProcessName()` + `ProcessListContains()`；`tests/unit/scope_logic.test.ahk` 已覆盖大小写归一化与作用域重叠逻辑。
- 修复方向: 无需继续处理。
- 验证方式: `AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\unit\scope_logic.test.ahk`；并在目标/非目标进程间切焦手工确认生效边界。

---

## BUG-004: 路径 C 长按连续触发缺少显式 KeyUp 停止
- 状态: 已修复
- 严重度: High
- 置信度: 高
- 文件: `src/core/HotkeyEngine.ahk:571`, `src/core/HotkeyEngine.ahk:833`
- 影响范围: 透传模式长按连续触发、按键释放精度
- 复现条件: 配置路径 C 映射并开启 `HoldRepeat`，按住后在重复间隔之间松开源键
- 当前观察: 已为路径 C 的 `sourceKey` 按需注册 `Up` 热键，并统一通过 `StopHoldTimer()` 清理长按定时器；快速松键与慢速松键都可在松开时停止连续触发，轮询逻辑继续保留为兜底。
- 修复方向: 无需继续处理；若后续出现滚轮类 `sourceKey` 的边界行为，再单独补充验证。
- 验证方式: 已手工验证路径 C 长按映射的快速松键、慢速松键与修饰键松开停止场景。

---
## BUG-005: `CapturePolling` 峰值保留逻辑可能丢失等长组合变化
- 状态: 待验证
- 严重度: Low
- 置信度: 低
- 文件: `src/core/KeyCapture.ahk:233`
- 影响范围: 按键捕获实时显示、复杂组合修正体验
- 复现条件: 按下 3 键后松开其中 1 键，再补按另一个键，使总键数保持不变
- 当前观察: 当前代码仍只在 `totalPressed >= CaptureKeys.Length` 时更新最大组合。理论上如果组合内容变化但总数不变，旧组合仍可能被保留下来；仓库内暂无针对该边界的直接回归测试。不过“全部松开后确认”的交互降低了实际影响。
- 修复方向: 如需优化体验，可在“数量相等但组合内容不同”时也刷新 `CaptureKeys`。
- 验证方式: 在编辑映射窗口中重复输入多组复杂组合；确认最终捕获结果是否总能反映用户最后保持按住的组合。

---

## BUG-006: `ProcessPickerOpen` 的清理职责分散在确认/关闭两条路径
- 状态: 已确认非问题
- 严重度: Low
- 置信度: 高
- 文件: `src/shared/Utils.ahk:102-106`, `src/shared/Utils.ahk:133-186`
- 影响范围: 代码可读性、进程选择器状态维护
- 复现条件: 阅读 `OnProcessPickOK()` 与 `CloseProcessPicker()` 的状态清理逻辑。
- 当前观察: 当前实现把确认路径的状态复位放在 `OnProcessPickOK()`，把取消/窗口关闭路径的状态复位放在 `CloseProcessPicker()`。`Gui.Destroy()` 不会额外触发 `Close` 事件，因此这不是“同一路径重复置 `false`”的问题，更接近分支职责拆分。
- 修复方向: 无需作为 bug 继续跟踪；若后续重构进程选择器，可顺手把状态清理收拢到单一出口。
- 验证方式: 打开并关闭进程选择器；确认可重复打开、取消、确认，且不会出现“选择器已打开”的残留状态。

---

## BUG-007: `OnEditMapping` 同时兼容双击与按钮点击参数
- 状态: 已确认非问题
- 严重度: Low
- 置信度: 高
- 文件: `src/ui/GuiEvents.ahk:305`
- 影响范围: 映射编辑入口
- 复现条件: 分别从 ListView 双击和“编辑映射”按钮进入编辑流程
- 当前观察: `OnEditMapping(ctrl, rowNum := 0, *)` 通过 `if (ctrl = MappingLV)` 区分两个入口，空白区域双击返回、按钮点击读取焦点行，当前逻辑自洽。
- 修复方向: 无需修改。若后续有人再疑惑，可补一行注释解释双入口设计。
- 验证方式: 双击有效行、双击空白区域、点击“编辑映射”按钮，确认行为均符合预期。

---

## BUG-008: `CanonicalizeProcessScope` 的手写排序属于性能优化，不是功能缺陷
- 状态: 已确认非问题
- 严重度: Low
- 置信度: 高
- 文件: `src/core/HotkeyEngine.ahk:259`
- 影响范围: 进程作用域规范化性能
- 复现条件: 构造超大量进程名列表
- 当前观察: 这里的 O(n2) 排序在当前数据规模下可接受，没有已知错误结果。它更像潜在优化项，不应作为 active bug 处理。
- 修复方向: 无需作为 bug 修复；若未来出现大规模列表性能瓶颈，再转入优化项处理。
- 验证方式: 仅在性能需求变化时重新评估，无需纳入常规 bug 修复回归。

---

## BUG-009: 路径 C 未命中组合时未完整保留原始输入语义
- 状态: 已修复
- 严重度: Medium
- 置信度: 高
- 文件: `src/core/HotkeyEngine.ahk:559`, `src/core/HotkeyEngine.ahk:801`
- 影响范围: 透传模式、修饰键原始功能保留的一致性
- 复现条件: 配置路径 C 映射后，在未按住目标 `modKey` 的情况下，按住其他修饰键再触发 `sourceKey`
- 当前观察: 路径 C 现已改为“统一事件路由 + 修饰键会话”模型。`sourceKey` 始终由 Path C 路由层接管，但只有在存在活跃的目标修饰键会话且命中对应映射时才转发为 `targetKey`；否则会立即回退发送原始 `sourceKey`，从而避免无关修饰键场景下的语义损坏。
- 修复方向: 无需继续处理；如果后续要支持更复杂的跨作用域按键切换，可另开优化项讨论。
- 验证方式: 已手工验证裸按、按住无关修饰键、按住目标修饰键，以及 `RButton` 手势场景。
---
## BUG-010: 路径 B 修饰键恢复对鼠标修饰键可能产生副作用
- 状态: 已修复
- 严重度: Medium
- 置信度: 高
- 文件: `src/core/HotkeyEngine.ahk:662-670`
- 影响范围: 路径 B、鼠标键作为修饰键时的恢复逻辑
- 复现条件: 旧实现会对所有修饰键执行恢复发送，鼠标修饰键可能被错误模拟为点击。
- 当前观察: `RestoreModKeyCallback()` 现已通过 `ShouldRestoreModifierOnSoloPress()` 跳过鼠标修饰键；`tests/integration/hotkey_pathAB.test.ahk` 已覆盖 `RButton`、`MButton`、`XButton1`、`XButton2` 的回归场景。
- 修复方向: 无需继续处理。
- 验证方式: `AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\integration\hotkey_pathAB.test.ahk`；并手工确认键盘修饰键仍可正常恢复，鼠标修饰键不会产生额外点击。

---

## BUG-011: `SaveConfig` 覆盖写入不会残留旧 Mapping 节
- 状态: 已确认非问题
- 严重度: Low
- 置信度: 高
- 文件: `src/core/Config.ahk:270`
- 影响范围: 配置保存、INI 节覆盖
- 复现条件: 删除若干映射后再次保存同一配置
- 当前观察: 当前实现采用“完整写入临时文件后覆盖原文件”的原子写入方式，旧文件中的多余节不会保留，结论与原疑虑相反。
- 修复方向: 无需修改。
- 验证方式: 新增多条映射后删除其中部分并保存；重新打开对应 INI；确认旧的 `MappingN` 节不会残留。

---

## BUG-012: 非编译模式自启路径的空格问题不是实际缺陷
- 状态: 已确认非问题
- 严重度: Low
- 置信度: 高
- 文件: `src/shared/Utils.ahk:216`
- 影响范围: 注册表自启命令拼接
- 复现条件: 在路径包含空格的环境下启用开机自启
- 当前观察: 当前命令已经对解释器路径和脚本路径分别加双引号，足以处理空格。至于路径包含双引号本身，在 Windows 合法路径中不成立，因此不构成实际 bug。
- 修复方向: 无需修改。
- 验证方式: 将脚本放在带空格路径下启用自启；重启或检查注册表值；确认命令格式正确。

---

## BUG-013: 已并入 BUG-009
- 状态: 已合并
- 严重度: Medium
- 置信度: 高
- 文件: `src/core/HotkeyEngine.ahk:708`
- 影响范围: 同 BUG-009
- 复现条件: 同 BUG-009
- 当前观察: 原条目关注 fallback `Send` 可能触发自身热键，实质上属于同一段 fallback 转发逻辑的风险讨论。后续统一在 BUG-009 下跟踪，避免重复修复或重复讨论。
- 修复方向: 以 BUG-009 为准。
- 验证方式: 以 BUG-009 为准。

---

## BUG-014: 模态窗口 `Close` 闭包持有 GUI 引用的 GC 风险缺少证据
- 状态: 已确认非问题
- 严重度: Low
- 置信度: 低
- 文件: `src/ui/GuiMain.ahk:133`
- 影响范围: 模态窗口销毁、GUI 对象回收
- 复现条件: 高频创建和销毁模态窗口，并观察内存或句柄变化
- 当前观察: 目前没有观察到泄漏或异常销毁行为；结合 AHK GUI 事件语义，窗口销毁后事件回调会一并释放，现有“闭包捕获 `modalGui` 导致持续 GC 风险”的推断缺少证据支持。
- 修复方向: 无需作为 bug 继续跟踪；若后续出现句柄增长或内存异常，再单独立项。
- 验证方式: 打开和关闭多个模态窗口；确认未出现窗口无法销毁、句柄持续增长或明显资源泄漏。

---

## 优化项（本次未整理）

以下优化项暂不纳入本次 bug 留档标准化范围，保留原记录供后续单独处理。

### OPT-001: 全量热键重载可优化为增量重载
- **类型**: ? 优化
- **文件**: `src/core/HotkeyEngine.ahk:140-142`
- **描述**: `ReloadConfigHotkeys(configName)` 当前直接调用 `ReloadAllHotkeys()`，即使只修改了一个配置也需要卸载并重新注册所有配置的热键。对于少量配置（<10）影响不大，但如果配置数量增多或映射条目很多，每次编辑映射都会触发全量重载。
- **修复方案**: 实现增量重载——仅卸载并重新注册被修改配置的热键。需要注意路径 C 的修饰键状态是跨配置共享的，需要小心处理。复杂度较高，可在性能成为瓶颈时实施。

---

### OPT-002: `GetRunningProcesses` 每次打开进程选择器都全量扫描
- **类型**: ? 优化
- **文件**: `src/shared/Utils.ahk:165-201`
- **描述**: 每次打开进程选择器都遍历所有窗口获取进程列表。如果系统窗口很多（>100），可能有可感知的延迟。
- **修复方案**: 可选：缓存进程列表，设定 TTL（如 5 秒），在 TTL 内复用缓存。优先级低。

---

### OPT-003: `DetectHotkeyConflicts` 使用 O(n2) 同组比较
- **类型**: ? 优化
- **文件**: `src/core/HotkeyEngine.ahk:212-234`
- **描述**: 对同一热键字符串下的所有条目做两两比较。在极端情况下（大量配置映射相同热键），性能可能不理想。但实际使用中同一热键出现在多个配置中的情况很少。
- **修复方案**: 当前实现足够。如果未来需要，可以用 Map 做去重优化。优先级极低。

---

### OPT-004: 按键捕获轮询可考虑使用 `Input` 命令替代
- **类型**: ? 优化
- **文件**: `src/core/KeyCapture.ahk`
- **描述**: 当前使用 30ms 轮询 `GetKeyState` 检测按键。AHK v2 的 `InputHook` 提供了事件驱动的按键检测，可以减少 CPU 占用并提高响应精度。但 `InputHook` 对鼠标按键支持有限，且当前的"松开时确认"机制需要同时追踪多键状态，`InputHook` 可能不完全适用。
- **修复方案**: 可部分使用 `InputHook` 替代键盘轮询，鼠标部分保留 `OnMessage`。改动较大，需要充分测试。优先级中等。

---

### OPT-005: `RefreshConfigList` 每次调用 `GetConfigList()` 重新扫描文件系统
- **类型**: ? 优化
- **文件**: `src/core/Config.ahk:146-180`
- **描述**: `RefreshConfigList` 通过 `GetConfigList()` 扫描 `configs/*.ini` 获取配置列表，而不是直接使用已加载的 `AllConfigs`。这导致每次刷新都有一次文件系统 IO。由于配置目录中文件数量通常很少，影响微乎其微。
- **修复方案**: 可选：从 `AllConfigs` 提取名称列表而非重新扫描文件系统。优先级极低。

---

### OPT-006: 测试 runner 缺少并发隔离与输出目录隔离
- **类型**: ? 优化
- **文件**: `scripts/test.ps1`
- **描述**: 当前 test runner 在每次执行前都会清空 `test-results/`，并共享同一套日志与截图输出路径。若同一 worktree 内并行运行多个 suite，结果目录会互相覆盖，`gui` suite 还会与其他本地验证争用桌面会话与 AutoHotkey 运行资源，导致假卡死、结果混杂或误判。
- **修复方案**: 为 runner 增加 run-level lock，以及可选的 `-OutputDir` / run-id 隔离；在检测到已有测试运行时直接拒绝第二个实例。完成这些隔离前，仓库规则应保持“同一 worktree 串行跑测试，`gui` suite 独占执行”。

---

## BUG-015: 路径 C 使用 RButton + 滚轮时右键菜单行为不稳定
- 状态: 已修复
- 严重度: Medium
- 置信度: 高
- 文件: `src/core/HotkeyEngine.ahk`
- 影响范围: 使用 `RButton` 作为路径 C 修饰键的鼠标手势（特别是按住右键 + 滚轮）
- 复现条件: 配置路径 C 映射（`modKey=RButton`，`sourceKey=Wheel*`），按住右键滚动滚轮后松开右键
- 当前观察: Path C 已重构为“显式修饰键会话 + 统一事件路由”模型：RButton 会话在本次按压期间一旦触发任何 Path C 映射，就被标记为手势会话（`isGesture = true`）。此时引擎不会拦截或模拟 RButton 物理事件，而是在松开后短延迟发送 Escape，尽量关闭可能出现的右键菜单；若本次按压未触发 Path C 映射，则整个右键过程保持原生透传。
- 修复方向: 通过中央映射表 `PathCMappingByModSource` 与 `PathCModSessions` 会话状态机统一处理所有 Path C 映射，并把 Path C 的职责明确收敛为“优先保留修饰键原始交互”。对 RButton 来说，浏览器右键手势、网页应用右键拖拽画布等交互始终依赖真实的按下/移动/松开序列；菜单抑制仅作为手势会话结束时的 Escape 兜底，而非绝对保证。
- 验证方式: 使用 2.5.0 及以上版本执行以下测试：启用 RButton + Wheel* Path C 映射后，浏览器右键手势与 Web 应用右键拖拽画布仍可正常工作；按住右键 + 滚轮（含多次滚动与快速滚动）后松开右键时，菜单应在常见应用中被快速关闭且不影响手势链路；开启 `HoldRepeat` 时，RButton 松开应稳定停止 repeat。少数应用仍可能出现轻微菜单闪烁，这属于 Path C 透传优先模型下的已知取舍。

---

## BUG-016: 路径 C 的 Wheel* 全局路由会误伤浏览器 Ctrl+滚轮缩放
- 状态: 已修复
- 严重度: Medium
- 置信度: 高
- 文件: `src/core/HotkeyEngine.ahk`
- 影响范围: Path C 的滚轮源键路由、浏览器 / WebView 的原生 `Ctrl+Wheel` 语义
- 复现条件: 配置 `RButton + Wheel*` 路径 C 映射后，在未按住 `RButton` 的情况下按住 `Ctrl` 滚动滚轮
- 当前观察: Path C 现为 `Wheel*` 源键增加 `PathC_ShouldRouteWheelSource()` 路由谓词。只有存在非 `Idle` 的目标修饰键会话，且当前前台窗口至少命中一条对应的 Path C 映射时，滚轮才会被 Path C 接管；否则原生滚轮事件会直接透传，从而恢复浏览器 `Ctrl+Wheel` 缩放等原始行为。
- 修复方向: 保留 2.5.0 引入的 Path C 会话状态机、`RButton` 透传和菜单收尾逻辑，仅收紧 `Wheel*` 的路由条件；不回退到旧版“按下修饰键时动态启停 source hotkey”的架构。
- 验证方式: 启用 `RButton + Wheel*` Path C 映射后，浏览器 `Ctrl+Wheel` 缩放恢复；`RButton + Wheel*` 仍正常触发映射；浏览器右键手势、Web 画布右键拖拽和 `RButton + Wheel*` 后的菜单关闭行为保持正常。
