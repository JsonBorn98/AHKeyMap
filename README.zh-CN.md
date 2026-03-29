<p align="center">
  <img src="assets/icon.ico" alt="AHKeyMap 图标" width="96">
</p>

# AHKeyMap

[English](README.md) | **简体中文**

AHKeyMap 是一个基于 AutoHotkey v2 的鼠标/键盘按键映射工具，支持多配置并行生效与进程作用域控制，适合打造自己的快捷键工作流。

## 适合谁用

- 想把鼠标按键或滚轮映射成键盘快捷键的人
- 同一套快捷键需要在不同软件里有不同效果的人
- 希望一键切换/启用多套配置的人

## 快速开始

### 运行（脚本模式）

1. 安装 AutoHotkey v2
2. 双击运行 `src\AHKeyMap.ahk`（或用 `AutoHotkey64.exe src\AHKeyMap.ahk` 运行）

### 编译（生成 EXE）

双击 `build.bat` 会先弹出一个简单菜单，让你选择：

- `Safe build`：先跑 `unit,integration`，再编译
- `Full build`：先跑 `all`，再编译
- `Quick build`：跳过测试，直接编译

这三种模式都会把产物写到统一的 `dist/` 目录。

如果你需要高级参数或脚本化调用，再直接使用 `scripts/build.ps1`。底层 PowerShell 脚本会自动寻找 Ahk2Exe 和 v2 基础文件，并生成 `dist/AHKeyMap.exe`。

## 自动化测试

AHKeyMap 现在已经带有一套自动化回归测试，用来覆盖配置读写、热键引擎核心逻辑，以及主界面的轻量冒烟流程。

本地跑完整套测试：

```powershell
pwsh ./scripts/test.ps1 -Suite all
```

只跑较快的非 GUI 测试：

```powershell
pwsh ./scripts/test.ps1 -Suite unit,integration
```

当前测试分层：

- `unit`：纯函数、格式转换、作用域逻辑
- `integration`：配置读写、冲突检测、热键引擎状态
- `gui`：主界面配置流程的冒烟测试

每个 `*.test.ahk` 都会在独立的 AutoHotkey 进程里执行。测试运行时会使用隔离的临时配置目录，不会改写你真实的 `configs/`。
测试产物会输出到 `test-results/`：

- `logs/`：每个测试文件一份详细日志，包含测试文件信息、每条用例的 `START` / `PASS` / `FAIL` 记录，以及失败详情
- `screenshots/`：只有 GUI 测试失败时才会抓取桌面截图
- `summary.json`：机器可读的汇总结果，包含 suite / 状态 / 退出码等信息

像浏览器手势、真实全局热键、以及对键鼠物理输入时序很敏感的场景，目前仍然保留为手工端到端检查，说明放在 `tests/manual/`。

## 基本操作

- 新建配置：主界面点击“新建”，输入名称并设置作用域
- 复制配置：选择已有配置，点击“复制”
- 启用/禁用：勾选/取消“启用”复选框
- 作用域模式：全局 / 仅指定进程 / 排除指定进程

## 配置文件说明（INI）

源码仓库模式下，配置文件位于仓库根目录的 `configs/`；打包后的 EXE 模式下，配置文件位于 `AHKeyMap.exe` 同级的 `configs/`。每个配置一个 `.ini`。

最小示例：

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
```

字段说明：

- `ProcessMode`：`global`（全局）/ `include`（仅指定）/ `exclude`（排除）
- `Process` / `ExcludeProcess`：进程名用 `|` 分隔
- `MappingN`：从 1 开始递增

## 热键模式说明

- 路径 A：不设置修饰键，直接把 `SourceKey` 映射到 `TargetKey`。
- 路径 B：设置修饰键，且 `PassthroughMod=0`。这会把修饰键当成纯热键修饰键使用，原始行为会被拦截。
- 路径 C：设置修饰键，且 `PassthroughMod=1`。这会保留修饰键本身的物理行为，适合浏览器右键手势、网页应用右键拖拽画布等依赖修饰键原始交互的场景。

补充说明：

- 如果你用鼠标键当修饰键，并且希望保留它原本的拖拽/手势能力，优先选择路径 C。
- 路径 C 对 `RButton` 的菜单抑制是“尽量而非保证”：触发过组合后，程序会在松开时尝试用 `Escape` 快速关闭菜单，但少数应用里仍可能有轻微闪烁。

## 常见问题

### 1. 热键没触发，应该先检查什么？

- 是否在脚本模式下运行了 AutoHotkey v2，或启动了最新版本的 `AHKeyMap.exe`。
- 当前配置是否在下拉框中选中，并勾选了“启用”。
- 作用域是否匹配：
  - `ProcessMode=include` 时，前台进程名需要在 `Process` 列表里。
  - `ProcessMode=exclude` 时，前台进程名不能在 `ExcludeProcess` 里。
  - 纯 `global` 模式对所有进程生效。
- 是否同时有其他键鼠工具/全局热键占用了相同组合（如别的 AHK 脚本、鼠标驱动、Steam、游戏内置快捷键等）。
如果这些都正常，但仍然不触发，可以先简化成一个最小配置（一个按键 → 一个目标）来排查。

### 2. 修改配置之后，需要重启软件吗？

不需要。  
在界面里新建、复制、编辑配置并点击保存后，程序会自动：

- 写回对应的 `configs/xxx.ini`；
- 同步启用状态到 `_state.ini`；
- 调用热键引擎重新加载所有已启用配置。

只有在你 **直接手改 INI 文件** 而没有通过 UI 时，才建议关掉再重启一次应用，让内存状态和磁盘配置重新对齐。

### 3. `_state.ini` 可以手动删掉吗？

可以删，但通常没必要。  
`_state.ini` 只保存「最后查看的配置名」、各配置的启用开关，以及 UI 语言偏好（`UILanguage`），不存真正的映射内容。删除后：

- 下次启动时会按实际的 `configs/*.ini` 自动重建启用状态；
- UI 会从第一个可用配置开始展示；
- 如果之前切换过界面语言，删除后会回到默认英文界面。

如果你发现 `_state.ini` 里有看起来“多余”的配置名，直接用应用删除对应配置或者重启一次，程序会自动清理。

### 4. 多配置之间热键冲突会怎样表现？

当多个启用的配置定义了相同热键时：

- 引擎会按优先级处理：`include > exclude > global`；
- 会扫描所有映射，检测作用域重叠的冲突（包括路径 B/C 使用同一修饰键的场景）；
- 一旦发现冲突，主窗口底部状态栏会变成橙色，并显示“热键冲突/注册失败”的数量，点击即可查看详情列表。

如果你只是想「先用再说」，出现冲突时优先排查 include 配置是否写得过宽（例如 include 写成了太多进程或和其它配置作用域完全重叠）。

### 5. 路径 C（透传组合）有什么使用上的坑？

- 路径 C 会尽可能保留修饰键（如 `RButton`）本身的行为，只在“修饰键 + 源键”组合出现时执行映射。
- 为了兼顾浏览器等应用的右键菜单，`RButton` 的菜单抑制是“尽量而非绝对”：触发过 Path C 组合后，会尝试在松开时发送 `Escape` 来关闭弹出的菜单，但个别软件仍可能看到轻微闪烁或短暂菜单。
- 长按类 Path C 映射（`HoldRepeat=1`）在松键、修饰键松开或焦点切换时会停止定时器；如果你遇到异常持续触发，可以先简化映射（去掉长按），确认问题是否只出现在特定软件上。

如果你对 Path C 的行为有比较特殊的预期，建议先在单一应用里集中测试几组组合键，再逐步扩展到更多进程。

### 6. 怎么备份或迁移配置到另一台机器？

- 关闭 AHKeyMap（脚本或 EXE）。
- 拷贝整个 `configs/` 目录到新机器对应位置。
- 源码仓库模式：放在仓库根目录，与 `src/` 同级。
- EXE 模式：放在 `AHKeyMap.exe` 同级。
- 在新机器上启动 AHKeyMap，即可自动加载所有配置和启用状态。

如果你只想迁移部分配置，可以只复制对应的 `xxx.ini` 文件；启用状态会在新机器首次启动时自动初始化。

## 文档

- 给 AI/自动化代理用的开发规范：`AGENTS.md`
- 技术架构说明：`docs/architecture.md`
- 自动化测试代码：`tests/`

## 许可证

本项目基于 [MIT License](LICENSE) 开源。
