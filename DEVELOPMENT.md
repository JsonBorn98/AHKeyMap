# AHKeyMap 开发历程文档

> 本文档供后续 AI 或开发者接手扩展功能时参考。

## 项目概述

AHKeyMap 是一个基于 AutoHotkey v2 的鼠标/键盘按键映射工具，采用**模块化架构**（主入口 `AHKeyMap.ahk` + 7 个功能模块），使用 AHKv2 原生 `Gui` 构建界面，INI 格式保存配置。

核心能力：

- 多配置管理（新建/复制/切换/删除）
- **多配置同时生效**：所有已启用配置的热键同时加载，根据前台窗口自动切换
- **三态进程作用域**：全局生效 / 仅指定进程 / 排除指定进程
- 多进程绑定（配置支持多进程 `|` 分隔）
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

### v2.0 — 多配置并行生效 + 三态进程作用域

**核心架构变更：**

- 从"单配置激活"改为"多配置同时生效"：所有已启用配置的热键同时加载
- 新增 `AllConfigs` 全局数组，存储所有配置的完整数据
- 配置切换仅影响 GUI 显示，不再卸载/重载热键
- 热键引擎遍历所有已启用配置，每个配置使用独立的 `HotIf` 闭包条件

**三态进程作用域（互斥）：**

- `global`：全局生效，无条件匹配
- `include`：仅指定进程前台时生效（原有功能）
- `exclude`：排除指定进程，其余情况生效（新增）
- INI 新增 `ProcessMode` 和 `ExcludeProcess` 字段，向后兼容旧配置

**配置管理增强：**

- 新增配置复制功能（默认名 `原名_copy`，可改名）
- 新增启用/禁用复选框，控制配置是否参与热键注册
- `_state.ini` 新增 `[EnabledConfigs]` section 持久化各配置启用状态
- 状态栏显示已启用配置数量

**热键引擎重构：**

- `MakeProcessChecker(cfg)` 工厂函数：根据配置的 `processMode` 创建独立闭包
- `ReloadAllHotkeys()` 遍历所有已启用配置，按优先级注册（include > exclude > global）
- `RegisterConfigHotkeys(cfg)` 为单个配置注册所有热键
- `PassthroughHandlers` 使用 `configName|sourceKey` 作为分组键，避免跨配置冲突
- `AllProcessCheckers` 数组持有闭包引用，防止被 GC 回收

**GUI 改动：**

- 主窗口配置栏：新增"启用"复选框、"复制"按钮、"作用域"按钮（替代"修改进程"）
- 新建配置对话框：三态单选按钮 + 进程列表编辑
- 修改作用域对话框：三态单选按钮 + 进程列表编辑
- 进程显示文本根据模式显示不同文案（全局 / 仅 xxx / 排除 xxx）
- 状态栏显示"已启用 N/M 个配置"
- 所有弹窗改为模态窗口（`CreateModalGui`/`DestroyModalGui`），打开时禁用主窗口，防止重复打开
- 进程选择器使用 `ProcessPickerOpen` 全局标志 + `CloseProcessPicker` 函数防止重复打开（AHK v2 fat arrow 中不允许 `global` 关键字）

### v2.0.1 — Bug 修复

- 修复 ListView 中未启用长按连续触发的映射仍显示触发延迟和触发间隔数值的问题（`RefreshMappingLV` 增加条件判断）

### v2.1 — 开机自启

- 新增开机自启功能，通过注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 实现
- 托盘右键菜单新增「开机自启」勾选项，启动时自动读取注册表判断当前状态
- 支持脚本模式和编译 EXE 模式（`A_IsCompiled` 分支处理路径格式）

### v2.1.1 — Bug 修复：长按连续触发定时器泄漏

- **问题**：两个启用长按连续触发的映射（如 XButton1→PgDn、XButton2→PgUp）同时按下时，定时器可能无法正确停止，导致网页持续上下乱滚，只能关闭软件
- **根因**：`HoldDownCallback` 每次调用创建新的 `timerFn`（`Bind()` 产生新对象），重入时旧定时器引用被覆盖成为孤立定时器；`HoldUpCallback` 无法取消待触发的 `StartRepeat` 一次性延迟定时器
- **修复（三重防御）**：
  - `HoldDownCallback`：新增防御性清理，创建新定时器前先停止已有的 `fn` 和 `startFn`
  - `RepeatTimerCallback`：新增 `GetKeyState(sourceKey, "P")` 物理按键状态检查，源按键松开后自动停止定时器（自愈机制）；滚轮键跳过检查
  - `HoldUpCallback`：同时取消 `startFn`（延迟启动定时器）和 `fn`（重复定时器）
- 路径 A/B/C 的定时器创建逻辑同步更新

### v2.1.2 — Bug 修复：带修饰前缀的 SourceKey 长按报错

- **问题**：SourceKey 含修饰键前缀（如 `^+C` 表示 Ctrl+Shift+C）且启用长按连续触发时，`RepeatTimerCallback` 将 `^+C` 直接传入 `GetKeyState` 导致报错（`GetKeyState` 只接受纯按键名）
- **修复**：在 `RepeatTimerCallback` 中用 `RegExReplace` 剥离 `^ + ! #` 修饰前缀后再调用 `GetKeyState`

### v2.1.3 — Bug 修复：复制后删除配置崩溃

- **问题**：快速复制配置后立即删除时，程序崩溃并报错 "Critical Error: Invalid memory read/write"，错误发生在 `UnregisterAllHotkeys()` 的 `hk.Has("keyUp")` 调用处
- **根因**：快速复制后删除触发多次 `ReloadAllHotkeys()` 调用，某些边界情况下 `ActiveHotkeys` 数组中可能存在非 Map 类型的无效引用，直接调用 `hk.Has()` 方法触发内存访问错误
- **修复**：在 `UnregisterAllHotkeys()` 遍历 `ActiveHotkeys` 时增加防御性类型检查 `Type(hk) != "Map"`，跳过无效对象避免崩溃

### v2.2.0 — 模块化重构

**核心架构变更：**

- 从"单文件架构"（2072 行）改为"模块化架构"（主入口 + 7 个功能模块）
- 使用 `#Include` 指令组织模块，Ahk2Exe 编译时自动合并所有模块
- 提升代码可维护性，便于多人协作和后续扩展

**模块拆分方案（按功能领域）：**

```
AHKeyMap/
├── AHKeyMap.ahk              # 主入口（~150 行）
└── lib/
    ├── Config.ahk            # 配置管理（~300 行）
    ├── GuiMain.ahk           # 主窗口构建（~90 行）
    ├── GuiEvents.ahk          # GUI 事件处理（~400 行）
    ├── MappingEditor.ahk        # 映射编辑弹窗（~130 行）
    ├── KeyCapture.ahk           # 按键捕获（~440 行）
    ├── HotkeyEngine.ahk         # 热键引擎（~400 行）
    └── Utils.ahk               # 工具函数（~250 行）
```

**模块职责划分：**

- **Config.ahk**：配置文件加载/保存、配置列表管理、启用状态持久化
- **GuiMain.ahk**：主窗口布局构建、托盘菜单初始化、模态窗口创建
- **GuiEvents.ahk**：所有 GUI 事件处理（配置管理、映射管理、新建/删除/编辑）
- **MappingEditor.ahk**：映射编辑弹窗构建、编辑事件处理、按键捕获按钮逻辑
- **KeyCapture.ahk**："松开时确认"按键捕获机制、鼠标钩子、轮询逻辑
- **HotkeyEngine.ahk**：热键注册/卸载、三条路径实现、长按连续触发、修饰键状态追踪
- **Utils.ahk**：按键格式转换、进程选择器、开机自启

**技术细节：**

- 所有全局变量在主入口文件（AHKeyMap.ahk）中统一初始化
- 各模块文件使用 `global varName` 声明引用主文件中的全局变量
- 使用 `#Include` 指令在主入口文件中包含所有模块
- 编译时 Ahk2Exe 自动处理 `#Include`，无需额外配置
- 模块间通过全局变量和函数调用进行通信

**全局变量管理规则：**

- 主入口文件：在 `#Include` 之前初始化所有全局变量（包含默认值）
- 模块文件：仅使用 `global varName` 声明，不重复初始化
- 优势：避免变量初始化顺序问题，确保所有模块访问的都是同一个变量实例

**编译配置更新：**

- `build.bat` 需要指定正确的 base 文件路径（`AutoHotkey64.exe` 位于 `v2` 子目录）
- 编译命令示例：
  ```batch
  Ahk2Exe.exe /in "AHKeyMap.ahk" /out "AHKeyMap.exe" /icon "icon.ico" /base "v2\AutoHotkey64.exe"
  ```

## 文件架构

### AHKeyMap.ahk 模块划分（v2.2.0）

**主入口文件：**
- AHKeyMap.ahk（162 行）：全局变量定义（所有模块共享）、模块 #Include、托盘/窗口事件、启动入口

**lib/ 模块文件：**

| 模块文件 | 行数 | 说明 |
|---|---|---|
| Config.ahk | 320 | 配置管理：加载/保存配置、启用状态持久化、进程列表管理 |
| GuiMain.ahk | 102 | 主窗口构建：布局、控件创建、托盘菜单初始化、模态窗口创建 |
| GuiEvents.ahk | 393 | GUI 事件处理：配置管理（新建/删除/编辑）、映射管理（新增/删除/复制） |
| MappingEditor.ahk | 136 | 映射编辑弹窗：窗口构建、编辑事件、按键捕获按钮 |
| KeyCapture.ahk | 467 | 按键捕获："松开时确认"机制、鼠标钩子、轮询逻辑、按键名称处理 |
| HotkeyEngine.ahk | 418 | 热键引擎：注册/卸载、三条路径实现、长按连续触发、修饰键状态追踪 |
| Utils.ahk | 220 | 工具函数：按键格式转换、进程选择器、开机自启 |

**总计：** ~2218 行（分布在 8 个文件）

### 其他文件

| 文件 | 说明 |
|---|---|
| `build.bat` | 一键编译脚本，自动搜索 Ahk2Exe 和 base 文件（支持 scoop 安装路径） |
| `icon.ico` | 应用图标（"AK" 字母设计，Python Pillow 生成） |
| `configs/` | 运行时配置目录（.gitignore 已排除） |

### 项目文件统计（v2.2.0）

```
AHKeyMap/
├── AHKeyMap.ahk          162 行  (主入口 + 全局变量定义)
├── build.bat              ~70 行  (编译脚本)
├── icon.ico               -       (应用图标)
├── DEVELOPMENT.md         ~340 行 (本文档)
├── configs/               -       (运行时配置，.gitignore)
└── lib/                  ~2056 行(7个功能模块)
    ├── Config.ahk         320 行  (配置管理)
    ├── GuiEvents.ahk     393 行  (GUI 事件处理)
    ├── GuiMain.ahk       102 行  (主窗口构建)
    ├── HotkeyEngine.ahk   418 行  (热键引擎)
    ├── KeyCapture.ahk     467 行  (按键捕获)
    ├── MappingEditor.ahk  136 行  (映射编辑弹窗)
    └── Utils.ahk          220 行  (工具函数)
```

**总代码量：** ~2218 行（不含注释和空行）

## 配置文件格式

### INI 配置（v2.0）

```ini
[Meta]
Name=浏览器标签切换
ProcessMode=include
Process=msedge.exe|chrome.exe|firefox.exe
ExcludeProcess=

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

**Meta 字段说明：**

- `ProcessMode`：`global`（全局生效）/ `include`（仅指定进程）/ `exclude`（排除指定进程），三选一
- `Process`：仅 `include` 模式使用，`|` 分隔的进程名列表
- `ExcludeProcess`：仅 `exclude` 模式使用，`|` 分隔的排除进程名列表
- **向后兼容**：旧配置无 `ProcessMode` 时，`Process` 非空推断为 `include`，为空推断为 `global`

### 状态文件（`_state.ini`）

```ini
[State]
LastConfig=浏览器标签切换

[EnabledConfigs]
全局快捷键=1
浏览器标签切换=1
PS专用=0
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
4. **OnMessage 鼠标钩子**：仅能捕获发送到 AHK 自身窗口的消息，路径 C 的修饰键监控依赖 AHK 的 Hotkey 钩子
5. **多配置热键冲突**：当多个配置的条件同时满足且定义了相同热键时，AHK 按注册顺序匹配第一个满足条件的（include > exclude > global）
6. **排除模式精度**：排除模式作用于整个配置级别，无法精确到单条映射。需要排除单条映射时，推荐使用"复制配置 + 删除冲突映射 + 设为 include"的工作流
7. **全局变量管理**：模块化后需要手动管理跨文件共享的全局变量声明，增加维护成本（未来可考虑类封装）

## 开发环境

- AutoHotkey v2.0+（通过 scoop 安装）
- 编译器：Ahk2Exe（AutoHotkey 自带）
- 图标生成：Python + Pillow（`gen_icon.py`，已删除，图标已生成）
- 操作系统：Windows 10/11
