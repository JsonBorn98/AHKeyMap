# AHKeyMap 开发历程文档

> 本文档供后续 AI 或开发者接手扩展功能时参考。

## 项目概述

AHKeyMap 是一个基于 AutoHotkey v2 的鼠标/键盘按键映射工具，采用**单文件架构**（`AHKeyMap.ahk`），使用 AHKv2 原生 `Gui` 构建界面，INI 格式保存配置。

核心能力：
- 多配置管理（新建/切换/删除）
- 多进程绑定（配置仅在指定前台进程下生效，支持多进程 `|` 分隔）
- 自定义修饰键 + 源按键 -> 映射目标的组合键映射
- 长按连续触发（可配置延迟和间隔）
- 三种热键引擎路径（无修饰键 / 拦截式组合 / 状态追踪式组合）
- 按键捕获支持键盘、鼠标按键、滚轮，采用"松开时确认"机制支持组合键捕获
- 可编译为 EXE 分发，支持管理员提权

## 版本历史

### v1.0 — 基础功能

- 配置管理：INI 格式存储，支持新建/切换/删除配置
- 单进程绑定：每个配置可绑定一个进程名，使用 `HotIfWinActive` 条件热键
- 按键捕获：使用 `InputHook` + `OnMessage`（鼠标），支持键盘和鼠标侧键/中键
- 热键引擎：`Hotkey()` 动态注册，支持长按连续触发（`SetTimer` 实现）
- GUI：AHKv2 原生 Gui，ListView 显示映射列表，支持新增/编辑/复制/删除映射
- 管理员提权：GUI 按钮 + 托盘菜单项，通过 `*RunAs` 重启脚本
- 编译支持：`build.bat` + `Ahk2Exe` 编译指令 + 自定义 `icon.ico`

### v1.1 — 扩展映射模型

**数据模型扩展：**
- 每条映射新增 `ModifierKey`（自定义修饰键）和 `PassthroughMod`（是否保留修饰键原始功能）字段
- INI 配置文件同步更新读写

**多进程绑定：**
- `Process` 字段支持 `|` 分隔多个进程名（如 `msedge.exe|chrome.exe`）
- 热键条件从 `HotIfWinActive` 改为 `HotIf(CheckProcessMatch)` 自定义回调
- 修改进程对话框改为多行编辑，进程选择器支持多选

**按键捕获重写：**
- 废弃 `InputHook`（按下即结束，无法捕获组合键）
- 改为 `SetTimer` 每 30ms 轮询 `GetKeyState` + `OnMessage` 鼠标钩子
- "松开时确认"机制：实时显示当前按住的组合，保留按键数量峰值，全部松开后确认
- 新增 WheelUp/WheelDown、LButton/RButton 捕获支持
- 200ms 延迟启动避免捕获到点击"捕获"按钮的鼠标事件

**热键引擎三条路径：**
- 路径 A（无修饰键）：直接 `Hotkey(sourceKey, callback)`，与 v1.0 相同
- 路径 B（拦截式组合）：`Hotkey("modKey & sourceKey", callback)`，额外注册修饰键恢复热键
- 路径 C（状态追踪式组合）：`Hotkey(sourceKey, handler)` + `GetKeyState(modKey)` 检查，`~modKey` 前缀让物理事件通过保留手势功能，`ComboFiredState` 追踪是否触发过组合，松开时抑制副作用（如右键菜单）

**编辑弹窗扩展：**
- 新增修饰键输入行（捕获 + 清除按钮）
- 新增"保留修饰键原始功能"复选框（仅修饰键非空时可用）
- ListView 增加"修饰键"和"修饰键模式"列

## 文件架构

### AHKeyMap.ahk 模块划分

| 行范围（约） | 模块 | 说明 |
|---|---|---|
| 1-62 | 头部 + 全局变量 | 编译指令、全局状态、GUI 控件引用 |
| 63-87 | 启动入口 | `StartApp()` 初始化 |
| 88-249 | 配置管理 | `LoadConfig` / `SaveConfig` / `RefreshMappingLV` / 进程解析 |
| 250-314 | GUI 构建 | `BuildMainGui()` 主窗口布局 |
| 314-429 | 配置管理事件 | 新建/删除配置、修改进程对话框 |
| 429-512 | 映射管理事件 | 新增/编辑/复制/删除映射 |
| 512-636 | 映射编辑弹窗 | `ShowEditMappingGui()` + 控件事件 |
| 637-1074 | 按键捕获 | 轮询机制、鼠标钩子、`FinishCapture` / `CancelCapture` |
| 1075-1137 | 按键格式转换 | `KeyToDisplay` / `KeyToSendFormat` / `FormatKeyName` |
| 1138-1249 | 进程选择器 | `ShowProcessPicker` / `GetRunningProcesses` |
| 1250-1552 | 热键引擎 | `RegisterMapping`（三条路径）、回调函数、修饰键监控 |
| 1553-1582 | 托盘和窗口事件 | 关闭/显示/退出/提权 |

### 其他文件

| 文件 | 说明 |
|---|---|
| `build.bat` | 一键编译脚本，自动搜索 Ahk2Exe（支持 scoop 安装路径） |
| `icon.ico` | 应用图标（"AK" 字母设计，Python Pillow 生成） |
| `MouseWheelTapSwitch.ahk` | 参考脚本（旧版 AHKv1 鼠标滚轮切换标签页），用于对比兼容性 |
| `configs/` | 运行时配置目录（.gitignore 已排除） |

## 配置文件格式

```ini
[Meta]
Name=浏览器标签切换
Process=msedge.exe|chrome.exe|firefox.exe

[Mapping1]
ModifierKey=RButton
SourceKey=WheelUp
TargetKey=^+Tab
HoldRepeat=0
RepeatDelay=300
RepeatInterval=50
PassthroughMod=1

[Mapping2]
ModifierKey=RButton
SourceKey=WheelDown
TargetKey=^Tab
HoldRepeat=0
RepeatDelay=300
RepeatInterval=50
PassthroughMod=1
```

## 热键引擎详解

### 路径选择逻辑

```
ModifierKey 为空？ → 路径 A（普通热键）
ModifierKey 非空 + PassthroughMod=0？ → 路径 B（拦截式组合）
ModifierKey 非空 + PassthroughMod=1？ → 路径 C（状态追踪式组合）
```

### 路径 C 的关键机制

1. **不拦截修饰键**：用 `~modKey` 前缀注册，物理事件正常传递（保留手势/拖拽等）
2. **拦截触发键**：`Hotkey(sourceKey, handler)` 拦截触发键，回调中用 `GetKeyState(modKey, "P")` 检查修饰键状态
3. **组合状态追踪**：`ComboFiredState[modKey]` 记录本次按住期间是否触发过组合
4. **副作用抑制**：修饰键松开时，如果触发过组合，对 RButton 延迟发送 Escape 关闭右键菜单
5. **共享修饰键**：多条映射共享同一修饰键时，`ComboFiredState` 按修饰键名索引共享状态
6. **触发键分组**：同一 sourceKey 的多条路径 C 映射共享一个统一处理器 `PassthroughSourceHandler`，依次检查所有关联修饰键

## 已知限制

1. **路径 C 的右键菜单抑制**：使用延迟发送 Escape 关闭，不够优雅，在某些应用中可能有副作用
2. **按键捕获轮询列表**：仅包含 F1-F12（F13-F24 在多数键盘上 `GetKeyState` 会误报），符号键使用 VK 码
3. **路径 B 的组合热键**：`modKey & sourceKey` 语法会拦截修饰键的原始功能（手势等会丢失）
4. **单文件架构**：随着功能增加，文件已超过 1500 行，后续可考虑拆分模块
5. **OnMessage 鼠标钩子**：仅能捕获发送到 AHK 自身窗口的消息，路径 C 的修饰键监控依赖 AHK 的 Hotkey 钩子

## 开发环境

- AutoHotkey v2.0+（通过 scoop 安装）
- 编译器：Ahk2Exe（AutoHotkey 自带）
- 图标生成：Python + Pillow（`gen_icon.py`，已删除，图标已生成）
- 操作系统：Windows 10/11
