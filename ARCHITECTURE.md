# ARCHITECTURE

本文件面向维护者，描述 AHKeyMap 的核心架构与关键机制。

## 总览
- 语言：AutoHotkey v2
- 入口：`AHKeyMap.ahk`
- 结构：主入口 + 7 个功能模块
- 配置：`configs/*.ini`，状态文件 `_state.ini`

## 模块职责
- `AHKeyMap.ahk`：全局变量初始化、模块 `#Include`、启动入口
- `lib/Config.ahk`：配置加载/保存、配置列表管理、启用状态持久化
- `lib/GuiMain.ahk`：主窗口构建、托盘菜单初始化、模态窗口管理
- `lib/GuiEvents.ahk`：GUI 事件处理（新建/复制/删除/编辑/作用域）
- `lib/MappingEditor.ahk`：映射编辑弹窗与按键捕获入口
- `lib/KeyCapture.ahk`：按键捕获机制（轮询 + 鼠标钩子）
- `lib/HotkeyEngine.ahk`：热键注册/卸载、长按连续触发、修饰键逻辑
- `lib/Utils.ahk`：按键显示转换、进程选择器、自启功能

## 全局变量管理
- 所有全局变量只在 `AHKeyMap.ahk` 中定义并初始化。
- 模块中仅用 `global VarName` 进行引用，不重复初始化。

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
### 路径选择逻辑
- `ModifierKey` 为空：路径 A（普通热键）
- `ModifierKey` 非空且 `PassthroughMod=0`：路径 B（拦截式组合）
- `ModifierKey` 非空且 `PassthroughMod=1`：路径 C（状态追踪式组合）

### 路径 A（无修饰键）
- `Hotkey(sourceKey, callback)` 直接注册
- 支持长按连续触发（定时器）

### 路径 B（拦截式组合）
- 使用 `modKey & sourceKey` 组合热键
- 修饰键原始功能会被拦截
- 额外注册修饰键恢复热键

### 路径 C（状态追踪式组合）
- 使用 `~modKey` 保留修饰键物理事件
- `Hotkey(sourceKey, handler)` 检查修饰键状态
- 用 `ComboFiredState` 追踪本次按住期间是否触发组合
- 对右键菜单等副作用进行抑制处理

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

## 已知限制（维护者需知）
- 路径 C 的右键菜单抑制使用延迟发送 Escape，可能存在副作用。
- 组合热键冲突时按注册顺序匹配（优先级同上）。
- 排除模式是配置级别，无法细化到单条映射。

## 编译
- `build.bat` 自动寻找 Ahk2Exe 与 AutoHotkey v2 base。
- 编译命令等效于：
  `Ahk2Exe.exe /in "AHKeyMap.ahk" /out "AHKeyMap.exe" /icon "icon.ico" /base "...\AutoHotkey64.exe"`
