<p align="center">
  <img src="assets/icon.ico" alt="AHKeyMap icon" width="96">
</p>

# AHKeyMap

**English** | [简体中文](README.zh-CN.md)

AHKeyMap is an AutoHotkey v2–based keyboard and mouse remapping tool. It supports multiple configs active at the same time and process-scoped hotkeys, making it easy to build your own shortcut workflows.

## What It’s For

AHKeyMap is useful if you:

- Want to map mouse buttons or wheel actions to keyboard shortcuts.
- Need the same hotkey to behave differently in different applications.
- Use multiple hotkey “profiles” and want to quickly enable/disable them.

Typical scenarios include:

- Browser tab navigation with mouse gestures.
- App-specific shortcuts for editors, design tools, or games.
- Quickly toggling between work and gaming configs.

## Features

- Multiple configs stored as simple `.ini` files in `configs/`.
- Per-process scopes:
  - Global: active in all apps.
  - Include: active only in selected processes.
  - Exclude: active everywhere except selected processes.
- Three hotkey paths for modifier behavior:
  - Path A: simple remap without a modifier key.
  - Path B: intercepting combos (modifier blocks its original behavior).
  - Path C: passthrough combos (modifier keeps its native behavior, good for gestures).
- Long-press repeat with configurable delay and interval.
- Conflict detection across configs with a clickable status bar summary.
- Bilingual UI (English + Simplified Chinese), with language preference stored in `_state.ini`.

## Installation

### Option 1: Script mode

1. Install AutoHotkey v2 (64-bit).
2. Clone or download this repository.
3. Run `src\AHKeyMap.ahk` (double-click or run via `AutoHotkey64.exe src\AHKeyMap.ahk`).

### Option 2: Prebuilt EXE

Download `AHKeyMap.exe` from the GitHub Releases page and run it directly.

### Build your own EXE

If you want to build the executable yourself:

```bat
build.bat
```

When launched without arguments, `build.bat` shows a small interactive menu:

- `Safe build`: run `unit,integration`, then build
- `Full build`: run `all`, then build
- `Quick build`: skip tests and build immediately

All three modes write the packaged output to `dist/`.

For advanced or scripted usage, call `scripts/build.ps1` directly. The PowerShell script locates Ahk2Exe and the AutoHotkey v2 base and produces `dist/AHKeyMap.exe`.

## Automated Tests

AHKeyMap now includes an automated regression suite for config logic, hotkey-engine behavior, and a lightweight GUI smoke flow.

Run the full suite locally:

```powershell
pwsh ./scripts/test.ps1 -Suite all
```

Run only the fast non-GUI suites:

```powershell
pwsh ./scripts/test.ps1 -Suite unit,integration
```

Current suites:

- `unit`: pure helper / formatting / scope logic
- `integration`: config I/O, conflict detection, hotkey-engine state
- `gui`: in-process GUI smoke test for the main config workflow

Each `*.test.ahk` file runs in its own AutoHotkey process. Test runs use an isolated temporary config directory and do not modify your real `configs/` folder.
Artifacts are written to `test-results/`:

- `logs/`: one detailed log per test file, including suite metadata, per-test `START` / `PASS` / `FAIL` lines, and failure details when a case breaks
- `screenshots/`: desktop screenshots captured only when a GUI test fails
- `summary.json`: machine-readable run summary with suite / status / exit-code information

Real desktop input scenarios such as browser gestures, true global hotkeys, and timing-sensitive mouse/keyboard behavior are still tracked as manual end-to-end checks under `tests/manual/`.

## Quick Start

1. Launch AHKeyMap (script or EXE).
2. In the main window:
   - Click “New” to create a config.
   - Choose a name and set the process scope (global / include / exclude).
3. Add a mapping:
   - Click “Add mapping”.
   - Capture a modifier (optional), source key, and target key.
   - Optionally enable repeat and adjust delay/interval.
4. Save the mapping and make sure the config is checked as “Enable”.
5. Switch to your target application and test the new hotkey.

For a concrete example, the following mapping in INI form (under `configs/`) makes the right mouse button + wheel up switch browser tabs backward:

```ini
[Meta]
Name=Browser tab switch
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

## Config Files Overview

- In a source checkout, configs live in the repo-root `configs/` directory. In the packaged EXE build, the app uses a sibling `configs/` directory next to `AHKeyMap.exe`.
- All configs live as separate `.ini` files.
- Each config has:
  - `[Meta]` section: name and process scope.
  - `[MappingN]` sections: individual hotkey mappings.
- `_state.ini` stores:
  - Last selected config name.
  - Enabled/disabled flags per config.
  - UI language (`UILanguage`), currently `en-US` or `zh-CN`.

Basic fields:

- `ProcessMode`: `global`, `include`, or `exclude`.
- `Process` / `ExcludeProcess`: `|`-separated process names.
- `MappingN`:
  - `ModifierKey`, `SourceKey`, `TargetKey`
  - `HoldRepeat` (0/1)
  - `RepeatDelay`, `RepeatInterval` (ms)
  - `PassthroughMod` (0 = intercept, 1 = passthrough)

See [docs/architecture.md](docs/architecture.md) for a deeper description of the hotkey engine and config format.

## Bilingual UI

The AHKeyMap GUI currently supports:

- English (`en-US`)
- Simplified Chinese (`zh-CN`)

On first run (when `_state.ini` has no `UILanguage`), the app defaults to English and then persists your choice in `_state.ini`:

- `UILanguage=en-US` or `UILanguage=zh-CN`

You can change the UI language from the tray menu:

- Right-click the tray icon → `Language` → choose `English` or `简体中文`.
- The main window and tray menu are rebuilt immediately; a full process restart is not required.

The config file format itself is language-agnostic; only the UI strings are localized.

## Documentation

- Chinese user guide: [README.zh-CN.md](README.zh-CN.md)
- Architecture and implementation notes: [docs/architecture.md](docs/architecture.md)
- Agent/automation guidelines: [AGENTS.md](AGENTS.md)
- Automated test suites: `tests/`
- Deferred bug backlog: [docs/bug-backlog.md](docs/bug-backlog.md)

## License

AHKeyMap is released under the [MIT License](LICENSE).
