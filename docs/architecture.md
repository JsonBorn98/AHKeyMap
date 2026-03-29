# ARCHITECTURE

本文件面向维护者，描述 AHKeyMap 的核心架构与关键机制。

## 总览
- 语言：AutoHotkey v2
- 入口：`src/AHKeyMap.ahk`
- 结构：`src/` 下的主入口 + `core` / `shared` / `ui` 模块分层
- 配置：`configs/*.ini`，状态文件 `_state.ini`
- 自动化测试：`tests/*` + `scripts/test.ps1`

## 模块职责
- `src/AHKeyMap.ahk`：全局变量初始化、`APP_ROOT` 解析、模块 `#Include`、启动入口
- `src/core/Config.ahk`：配置加载/保存、配置列表管理、启用状态持久化（`SaveConfig` 和 `SaveEnabledStates` 均采用原子写入：先写临时文件再替换，防止中途失败丢失数据）
- `src/core/Localization.ahk`：本地化语言包与 `L(key, args*)` 辅助函数
- `src/ui/GuiMain.ahk`：主窗口构建、托盘菜单初始化、模态窗口管理（状态栏告警时显示独立“查看详情”入口，支持悬停提示与手型光标）
- `src/ui/GuiEvents.ahk`：GUI 事件处理（新建/复制/删除/编辑/作用域）；私有辅助函数 `RadioToProcessMode`、`ProcTextToStr`
- `src/ui/MappingEditor.ahk`：映射编辑弹窗与按键捕获入口
- `src/core/KeyCapture.ahk`：按键捕获机制（轮询 + 鼠标钩子）
- `src/core/HotkeyEngine.ahk`：热键注册/卸载、长按连续触发、修饰键逻辑；路径 A/B 直接注册，路径 C 由统一会话引擎路由；冲突检测包含跨路径 B/C 修饰键冲突
- `src/shared/Utils.ahk`：按键显示转换、进程选择器、自启功能

## 全局变量管理
- 所有全局变量只在 `src/AHKeyMap.ahk` 中定义并初始化。
- 模块中仅用 `global VarName` 进行引用声明，不重复初始化（重复赋值会在 `#Include` 时覆盖主入口的值）。
- `src/AHKeyMap.ahk` 通过 `APP_ROOT` 区分源码模式与编译模式：源码模式下根目录为仓库根，编译模式下根目录为 `AHKeyMap.exe` 所在目录，因此两种模式都会在各自根目录下使用 `configs/`。

## 自动化测试架构

### 测试入口
- 顶层入口：`scripts/test.ps1`
- Runner 会按目录约定发现测试文件，并把每个 `*.test.ahk` 作为独立 AutoHotkey 进程执行，等待退出码后再汇总结果。
- 测试文件按约定分层放在：
  - `tests/unit/*.test.ahk`
  - `tests/integration/*.test.ahk`
  - `tests/gui/*.test.ahk`
  - `tests/manual/`（暂不纳入阻塞式 CI）

### 测试隔离机制
- `src/AHKeyMap.ahk` 支持两个测试专用覆盖变量：
  - `__AHKM_TEST_MODE`：为 `true` 时跳过自动 `StartApp()`
  - `__AHKM_CONFIG_DIR`：测试时把配置目录重定向到临时目录，避免污染真实 `configs/`
- `DispatchSendHook` 可在测试中拦截 `Send()` 路径，用来验证“准备发送什么按键”，而不真的把输入发到桌面系统。

### 测试基建
- `tests/support/TestBase.ahk` 提供断言、临时目录清理、GUI/热键状态重置、发送捕获等公共能力。
- Runner 通过环境变量 `AHKM_TEST_LOG_FILE` 把每个测试文件对应的日志路径传给 `TestBase.ahk`，由测试进程直接写入 `test-results/logs/`。
- 日志格式以“人可读排障”为主：包含 `SUITE`、`STARTED`、每条用例的 `START` / `PASS` / `FAIL`、失败明细，以及 `SUMMARY`；若测试进程输出了 `stdout` / `stderr`，Runner 会在日志末尾追加对应片段。
- `test-results/summary.json` 是机器可读汇总，GUI 失败时可同时在 `test-results/screenshots/` 找到桌面截图。
- `gui` 层目前属于“进程内 GUI 冒烟测试”，验证主界面流程与磁盘状态，不做真实物理键鼠回放。
- 真实桌面输入、浏览器手势、时序敏感场景仍保留为手工 E2E 检查。

## 配置文件约定
### 配置 INI（每个配置一个文件）
- `[Meta]`：`Name`、`ProcessMode`、`Process`、`ExcludeProcess`
- `[MappingN]`：从 1 开始递增
- `ProcessMode`：`global` / `include` / `exclude`
- 进程列表用 `|` 分隔

### 状态文件 `_state.ini`
- `[State]`：`LastConfig`、`UILanguage`
- `[EnabledConfigs]`：每个配置的启用标记（1/0）

## 热键引擎（三条路径）

`RegisterMapping` 根据 `ModifierKey` 与 `PassthroughMod` 分发到三个路径函数。

### 路径选择逻辑
- `ModifierKey` 为空 → `RegisterPathA`（普通热键）
- `ModifierKey` 非空且 `PassthroughMod=0` → `RegisterPathB`（拦截式组合）
- `ModifierKey` 非空且 `PassthroughMod=1` → `RegisterPathCMapping`（路径 C 映射表，统一由 Path C 引擎处理）

### 路径 A — `RegisterPathA`（无修饰键）
- `Hotkey(sourceKey, callback)` 直接注册
- 支持长按连续触发（定时器）

### 路径 B — `RegisterPathB`（拦截式组合）
- 使用 `modKey & sourceKey` 组合热键
- 修饰键原始功能会被拦截
- 额外注册修饰键恢复热键（同 HotIf 条件下仅注册一次）
- 适合不需要保留修饰键原始行为的组合键场景

### 路径 C — Path C 引擎（状态机 + 统一路由）
- 配置层：`ModifierKey` 非空且 `PassthroughMod=1` 的映射在注册阶段不会直接绑定 Hotkey 回调，而是写入 `PathCMappingByModSource` 映射表，按 `modKey "|" sourceKey` 分组。
- 运行时：在 `ReloadAllHotkeys` 末尾，统一为所有出现过的 `modKey`、`sourceKey` 注册一组“事件路由 Hotkey”：
  - 修饰键：全部使用 `~modKey` / `~modKey Up` 透传物理事件，保证拖拽/浏览器右键手势等外部逻辑可以看到完整的 RButton 按下/移动/松开序列。
  - 源键：非滚轮键使用 `*sourceKey` / `*sourceKey Up`；滚轮键使用 `*sourceKey`，并通过 `PathC_ShouldRouteWheelSource()` 仅在存在命中的 Path C 会话时拦截，从而保留浏览器 `Ctrl+Wheel` 等原生语义。
- 设计目标：优先保留修饰键原始交互，再在这个基础上叠加按键映射；对 `RButton` 而言，浏览器右键手势、网页应用里的右键拖拽画布等能力优先于“绝对不闪菜单”。
- Path C 引擎内部维护每个修饰键的会话状态：
  - `state`: `"Idle"` / `"HeldNoCombo"` / `"GestureActive"`
  - `isGesture`: 当前按下周期是否触发过任意 Path C 组合
  - `activeSources`: 当前会话下参与 repeat 的源键
  - `repeatMappings`: 当前会话下正在 repeat 的映射 ID 集合
- 源键按下时，Path C 引擎按以下规则决策：
  - 遍历所有 `state != "Idle"` 的修饰键会话，对每个 `modKey "|" sourceKey` 在映射表里查找候选条目。
  - 通过配置层生成的 `checker` 闭包判断进程作用域是否命中；命中后触发映射，并将会话标记为 `GestureActive` / `isGesture = true`。
  - 若映射开启 `HoldRepeat`，使用现有 `HoldTimers` + `RepeatTimerCallback(sendKey, sourceKey, idx, modKey)` 机制启动定时器，并将 `mapping.id` 记入会话。
  - 若未命中任何 Path C 映射，则回退发送原始 `sourceKey`；对于 `Wheel*`，如果当前根本不存在可命中的 Path C 会话，路由热键不会激活，原生滚轮事件会直接透传。
- 修饰键松开时：
  - 对非 RButton：无论是否触发过组合，只执行 Path C 内部清理逻辑（停止 repeat、清空会话），修饰键物理语义由 `~modKey` 透传负责。
  - 对 RButton：一旦 `isGesture = true`，本次按压被视为“手势右键”，Path C 引擎会在短延迟后发送一次 Escape 尝试关闭可能出现的右键菜单；若 `isGesture = false`，本次按压完全交由系统处理。

## 进程作用域（HotIf）
- `include`：前台进程匹配列表时生效
- `exclude`：前台进程不在排除列表时生效
- `global`：不设置 HotIf
- 优先级：`include > exclude > global`

## 按键捕获机制
- 轮询 `GetKeyState` 捕获键盘按键
- `OnMessage` 捕获鼠标按键/滚轮
- “松开时确认”机制：全部松开后确认组合键
- 捕获开始时延迟 200ms，避免误捕点击事件
- 捕获窗口失焦时自动取消，防止后台误捕

## 配置名限制
- 不允许包含 `\ / : * ? " < > | = [ ]`（用于文件名和 INI 键名，特殊字符会导致文件创建失败或数据损坏）。

## 已知限制（维护者需知）
- 路径 C 使用 `RButton` 作为修饰键时，只要本次按下期间触发过路径 C 组合，这一次按压将被视为手势操作；引擎会在松开后短延迟发送 Escape 尽量关闭右键菜单，但不保证所有应用中完全无闪烁。未触发组合的普通右键点击仍按原生事件路径处理。
- 组合热键冲突时按注册顺序匹配（优先级同上）。
- 排除模式是配置级别，无法细化到单条映射。

## 编译
- `build.bat` 是给本地 Windows 用户的交互式入口：无参数运行时会先显示 `Safe build` / `Full build` / `Quick build` 三种模式，再调用底层脚本。
- `Safe build` = `unit,integration -> build`；`Full build` = `all -> build`；`Quick build` = 直接 build。
- 根目录 `build.bat` 不承担高级参数透传，保持“人用入口”语义；需要高级构建参数时，直接调用 `scripts/build.ps1`。
- `scripts/build.ps1` 负责实际编译与打包，并自动寻找 Ahk2Exe 与 AutoHotkey v2 base。
- 编译命令等效于：
  `Ahk2Exe.exe /in "src\AHKeyMap.ahk" /out "dist\AHKeyMap.exe" /icon "assets\icon.ico" /base "...\AutoHotkey64.exe"`

## 多语言支持 / Localization

- UI 语言通过 `L(key, args*)` 辅助函数集中管理，实现在 `src/core/Localization.ahk`：
  - 使用 `CurrentLangCode` 选择语言包，目前支持 `en-US` 和 `zh-CN`。
  - 文本键为扁平命名空间，例如：`GuiMain.ConfigLabel`、`GuiEvents.Error.ConfigExists`。
  - `L("Key", arg1, arg2)` 会调用 `Format` 进行占位符替换（`{1}`、`{2}`）。
- 语言包在内存中用 `Map()` 静态定义，如 `BuildEnPack()` / `BuildZhPack()`，后续如需外置 INI/JSON 只需改 `GetLangPack` 实现。
- UI 语言首选项存储在 `_state.ini`：
  - `[State]` 节下新增 `UILanguage` 键，值为 `en-US` 或 `zh-CN`。
  - 启动时优先读取 `_state.ini` 中的 `UILanguage`；若缺失，则默认使用英文 (`en-US`) 作为 UI 语言，不再根据操作系统语言自动切换。
- 托盘菜单提供语言切换入口：
  - `Language` 子菜单下有 `English` / `简体中文`，点击后更新 `CurrentLangCode` 并调用 `SaveEnabledStates()` 持久化。
  - 切换语言时不会重启整个脚本，而是会“软重启”主窗口：关闭当前主窗口和相关子窗口，再用新的 `CurrentLangCode` 重建主窗口和托盘菜单，保持配置与热键状态不变。
- 代码与文档语言约定：
  - 源代码中的标识符与注释统一使用英文，便于英语使用者维护；
  - 用户界面文案通过本地化层维护中英双语；
  - 开发者与 AI 之间的讨论可以使用中文，但最终落地到仓库的注释与技术文档应以英文为主。

