# AHKeyMap

AHKeyMap 是一个基于 AutoHotkey v2 的鼠标/键盘按键映射工具，支持多配置并行生效与进程作用域控制，适合打造自己的快捷键工作流。

## 适合谁用

- 想把鼠标按键或滚轮映射成键盘快捷键的人
- 同一套快捷键需要在不同软件里有不同效果的人
- 希望一键切换/启用多套配置的人

## 快速开始

### 运行（脚本模式）

1. 安装 AutoHotkey v2
2. 双击运行 `AHKeyMap.ahk`（或用 AutoHotkey64.exe 运行）

### 编译（生成 EXE）

双击 `build.bat`，脚本会自动寻找 Ahk2Exe 和 v2 基础文件并生成 `AHKeyMap.exe`。

## 基本操作

- 新建配置：主界面点击“新建”，输入名称并设置作用域
- 复制配置：选择已有配置，点击“复制”
- 启用/禁用：勾选/取消“启用”复选框
- 作用域模式：全局 / 仅指定进程 / 排除指定进程

## 配置文件说明（INI）

配置文件位于 `configs/`，每个配置一个 `.ini`。

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

## 常见问题

### 1. 为什么 `_state.ini` 里有多余配置名？

`_state.ini` 用于保存 UI 状态和启用状态。历史残留的键不会影响功能，程序会在启动时同步清理。

### 2. 多配置之间有冲突会怎样？

当多个配置同时生效且定义相同热键时，按注册优先级匹配：
`include > exclude > global`。

### 3. 配置文件改了，界面没更新？

建议在软件内操作配置；若手动改 INI，请重启软件刷新。

## 文档

- 给 AI/自动化代理用的开发规范：`AGENTS.md`
- 技术架构说明：`ARCHITECTURE.md`
