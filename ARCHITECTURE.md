# ARCHITECTURE

本文件面向维护者，描述 AHKeyMap 的核心架构与关键机制。

## 总览
- 语言：AutoHotkey v2
- 入口：`AHKeyMap.ahk`
- 结构：主入口 + 7 个功能模块
- 配置：`configs/*.ini`，状态文件 `_state.ini`

## 模块职责
- `AHKeyMap.ahk`：全局变量初始化、模块 `#Include`、启动入口
- `lib/Config.ahk`：配置加载/保存、配置列表管理、启用状态持久化（`SaveConfig` 和 `SaveEnabledStates` 均采用原子写入：先写临时文件再替换，防止中途失败丢失数据）
- `lib/GuiMain.ahk`：主窗口构建、托盘菜单初始化、模态窗口管理（状态栏告警时显示独立“查看详情”入口，支持悬停提示与手型光标）
- `lib/GuiEvents.ahk`：GUI 事件处理（新建/复制/删除/编辑/作用域）；私有辅助函数 `RadioToProcessMode`、`ProcTextToStr`
- `lib/MappingEditor.ahk`：映射编辑弹窗与按键捕获入口
- `lib/KeyCapture.ahk`：按键捕获机制（轮询 + 鼠标钩子）
- `lib/HotkeyEngine.ahk`：热键注册/卸载、长按连续触发、修饰键逻辑；路径 A/B 直接注册，路径 C 由统一会话引擎路由；冲突检测包含跨路径 B/C 修饰键冲突
- `lib/Utils.ahk`：按键显示转换、进程选择器、自启功能

## 全局变量管理
- 所有全局变量只在 `AHKeyMap.ahk` 中定义并初始化。
- 模块中仅用 `global VarName` 进行引用声明，不重复初始化（重复赋值会在 `#Include` 时覆盖主入口的值）。

## 配置文件约定
### 配置 INI（每个配置一个文件）
- `[Meta]`：`Name`、`ProcessMode`、`Process`、`ExcludeProcess`
- `[MappingN]`：从 1 开始递增
- `ProcessMode`：`global` / `include` / `exclude`
- 进程列表用 `|` 分隔

### 状态文件 `_state.ini`
- `[State]`：`LastConfig`
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
  - 源键：使用 `*sourceKey` / `*sourceKey Up`（滚轮类不注册 Up）。
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
  - 若未命中任何 Path C 映射，则回退发送原始 `sourceKey`。
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
- `build.bat` 自动寻找 Ahk2Exe 与 AutoHotkey v2 base。
- 编译命令等效于：
  `Ahk2Exe.exe /in "AHKeyMap.ahk" /out "AHKeyMap.exe" /icon "icon.ico" /base "...\AutoHotkey64.exe"`

