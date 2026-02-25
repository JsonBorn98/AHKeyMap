# AGENTS.md

Guidance for agentic coding in this repository.
This is a Windows AutoHotkey v2 app with a modular AHK layout.

## Sources of truth
- Cursor rules: `.cursor/rules/project.mdc` (always apply)
- Project architecture: `ARCHITECTURE.md`

## Repo map
- `AHKeyMap.ahk`: main entry, globals, startup, #Include list
- `lib/`: feature modules (Config, GUI, Hotkey engine, etc.)
- `build.bat`: build/compile script for Ahk2Exe
- `configs/`: runtime INI files (ignored by git)

## Build / run / test
### Build (compile to EXE)
- `build.bat`
  - Locates Ahk2Exe and AutoHotkey v2 base automatically.

### Run (script mode)
- Use AutoHotkey v2 interpreter on `AHKeyMap.ahk`.
  - Example (path varies): `AutoHotkey64.exe AHKeyMap.ahk`

### Lint
- No lint tooling configured in this repo.

### Tests
- No automated test harness in this repo.
- There is no single-test command; validate changes manually.

### Manual verification tips
- Launch app and open main GUI.
- Create/modify a config and ensure hotkeys reload.
- Verify `_state.ini` updates in `configs/` as expected.
- Exercise Hotkey paths A/B/C if your change touches engine logic.

## Cursor rule highlights (must follow)
- After each feature or fix, proactively ask whether to update
  documentation and create a git commit.
- Every change must update version in **both** places:
  - `AHKeyMap.ahk` line 13: `;@Ahk2Exe-SetVersion x.y.z`
  - `AHKeyMap.ahk` line 21: `global APP_VERSION := "x.y"`
- Versioning: new features bump minor, bug fixes bump patch.
- Commit messages should be Chinese, e.g. `v2.2.1: 功能描述` or
  `fix: 修复描述` (only if user asks for a commit).
- Do not modify existing code without user permission; read related
  code before changes.

## Include order and module boundaries
- `AHKeyMap.ahk` owns the `#Include` list. Current order is:
  - `lib/Config.ahk`
  - `lib/Utils.ahk`
  - `lib/HotkeyEngine.ahk`
  - `lib/KeyCapture.ahk`
  - `lib/GuiMain.ahk`
  - `lib/MappingEditor.ahk`
  - `lib/GuiEvents.ahk`
- Keep GUI construction in `GuiMain.ahk` and event handlers in
  `GuiEvents.ahk`.
- Hotkey registration/cleanup stays in `HotkeyEngine.ahk`.

## Code style guidelines
### Language and runtime
- AutoHotkey v2.0+ only; keep v2 syntax and APIs.
- Prefer simple, imperative style consistent with existing modules.

### File organization
- All globals are defined and initialized in `AHKeyMap.ahk`.
- Modules should only declare globals via `global VarName` and must
  not re-initialize them.
- Modules are included only from `AHKeyMap.ahk` via `#Include`.

### Naming
- Functions: PascalCase (e.g., `LoadAllConfigs`, `ReloadAllHotkeys`).
- Local variables: camelCase (e.g., `configName`, `procList`).
- Globals: PascalCase / UpperCamel (e.g., `CurrentConfigName`).
- Constants/app metadata: UPPER_SNAKE (e.g., `APP_NAME`).

### Formatting
- Indent with 4 spaces.
- Use double quotes for strings.
- Section headers use comment blocks with `; =====` style lines.
- Keep line lengths reasonable; prefer clarity over compactness.

### Imports / includes
- Use `#Include` only in `AHKeyMap.ahk`.
- New modules should follow the existing naming pattern and be added
  to the include list once.

### Data structures
- Use `Map()` for key/value data (configs, mappings, registries).
- Use arrays for ordered lists (configs, mappings, processes).
- Copy Map entries when duplicating config/mapping data.
- Coerce INI numeric values with `Integer()` as in existing code.

### Error handling and defensiveness
- Guard filesystem access with `FileExist` / `DirExist`.
- Wrap `IniRead/IniWrite/Hotkey` operations in `try` where failure
  should not crash the app.
- Use defensive checks when iterating dynamic structures
  (e.g., `Type(hk) != "Map"`).
- Prefer `MsgBox` with `APP_NAME` for user-facing errors.
- Always reset `HotIf()` after temporary use.
- Cancel timers/handlers on cleanup paths to avoid leaks.

### GUI and events
- Keep GUI creation in `GuiMain.ahk`; event handlers in `GuiEvents.ahk`.
- Use modal helpers (`CreateModalGui`, `DestroyModalGui`) for dialogs.
- Keep event handlers short; move logic into helper functions where
  it improves readability.
- UI strings are Chinese; keep wording consistent with existing labels.
- Update status text via `UpdateStatusText()` after relevant changes.

### Hotkey engine conventions
- Respect the A/B/C path logic for modifier handling.
- Keep process-scoped hotkeys using `HotIf` and `MakeProcessChecker`.
- Ensure timers and handlers are cleaned up in `UnregisterAllHotkeys`.
- Preserve include > exclude > global registration priority.
- Keep `AllProcessCheckers` references to prevent GC of closures.

### Config and state handling
- Config INI sections: `Meta`, then `Mapping1`, `Mapping2`, ...
- Mapping keys must remain: `ModifierKey`, `SourceKey`, `TargetKey`,
  `HoldRepeat`, `RepeatDelay`, `RepeatInterval`, `PassthroughMod`.
- `_state.ini` sections: `State` and `EnabledConfigs`.
- Use default values in `IniRead` for backward compatibility.

### Naming and key strings
- Process lists are `|` separated strings in INI, converted to arrays.
- Hotkey strings follow AHK v2 syntax (e.g., `RButton & WheelUp`).
- When needed, strip modifier prefixes before `GetKeyState`.

### Performance and safety
- AHK is single-threaded; keep callbacks quick and non-blocking.
- Avoid heavy work inside hotkey callbacks; delegate when possible.
- Always clean state maps when reloading hotkeys.

## INI configuration conventions
- Each config is a standalone `.ini` in `configs/`.
- `_state.ini` stores UI state and enabled config flags.
- `ProcessMode` values: `global`, `include`, `exclude`.
- Use `|` to separate multiple processes in `Process` / `ExcludeProcess`.

## Manual test focus (no automated tests)
- Config CRUD: new, copy, delete; verify dropdown and status count.
- Hotkeys: simple mapping, modifier mapping, passthrough mapping.
- Process modes: include and exclude with multiple processes.
- Long-press repeat: start/stop timers cleanly.

## Agent workflow guidance
- Read relevant module(s) before editing.
- Avoid touching unrelated files or reformatting large regions.
- If you see unexpected local changes, stop and ask the user.
- Keep edits minimal and aligned with existing patterns.
- Do not add new tooling unless user requests it.

## Optional docs update
- If you add features or fix bugs, consider updating documentation
  (ask the user first per Cursor rule).
