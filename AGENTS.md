# AGENTS.md

Guidance for agentic coding in this repository.
This is a Windows AutoHotkey v2 app with a modular AHK layout.

## Sources of truth
- Project architecture: `ARCHITECTURE.md`
- No Cursor rules or Copilot instructions are present in the repo.

## Repo map
- `AHKeyMap.ahk` — main entry, global variable initialization, `#Include` list, startup
- `lib/Config.ahk` (~345 lines) — config load/save (atomic write), config list management, enabled state persistence
- `lib/Utils.ahk` (~213 lines) — key display conversion, process picker, auto-start utilities
- `lib/HotkeyEngine.ahk` (~425 lines) — hotkey register/unregister, long-press repeat, modifier logic (paths A/B/C)
- `lib/KeyCapture.ahk` (~470 lines) — key capture mechanism (polling + mouse hook)
- `lib/GuiMain.ahk` (~102 lines) — main window construction, tray menu, modal window helpers
- `lib/MappingEditor.ahk` (~136 lines) — mapping edit dialog and key capture entry
- `lib/GuiEvents.ahk` (~390 lines) — GUI event handlers (config CRUD, scope editing)
- `configs/` — runtime INI files (gitignored)
- `build.bat` — compile script for Ahk2Exe
- `.gitignore` — ignores `AHKeyMap.exe`, `configs/`, `*.bak`, `*.tmp`

## Build / run / test

### Build (compile to EXE)
```
build.bat
```
Locates Ahk2Exe and AutoHotkey v2 base automatically (Program Files, LocalAppData, scoop).

### Run (script mode)
```
AutoHotkey64.exe AHKeyMap.ahk
```
Path varies by installation.

### Lint
No lint tooling configured.

### Tests
No automated tests. Validate changes manually:
- Launch app → open main GUI
- Create/modify a config → verify hotkeys reload
- Verify `_state.ini` updates in `configs/`
- Verify no `.tmp` files remain in `configs/` after save
- Exercise Hotkey paths A/B/C if your change touches engine logic
- Config CRUD: new, copy, delete; verify dropdown and status count
- Process modes: include and exclude with multiple processes
- Long-press repeat: start/stop timers cleanly

## Versioning (MUST follow)
Every change must update version in **both** places:
- `AHKeyMap.ahk` line 13: `;@Ahk2Exe-SetVersion x.y.z`
- `AHKeyMap.ahk` line 21: `global APP_VERSION := "x.y.z"`

Rules: new features bump minor, bug fixes bump patch. Both values must match.

## Commit conventions
- Only commit when user explicitly asks.
- Messages in Chinese: `v2.2.1: 功能描述` or `fix: 修复描述`.
- After each feature or fix, proactively ask the user whether to update
  documentation and create a git commit.

## Include order and module boundaries
`AHKeyMap.ahk` owns the `#Include` list. Current order:
1. `lib/Config.ahk`
2. `lib/Utils.ahk`
3. `lib/HotkeyEngine.ahk`
4. `lib/KeyCapture.ahk`
5. `lib/GuiMain.ahk`
6. `lib/MappingEditor.ahk`
7. `lib/GuiEvents.ahk`

Boundaries:
- GUI construction → `GuiMain.ahk`; event handlers → `GuiEvents.ahk`
- Hotkey registration/cleanup → `HotkeyEngine.ahk`
- New modules: add to `#Include` list in `AHKeyMap.ahk` only.

## Code style guidelines

### Language and runtime
- AutoHotkey v2.0+ only. No v1 syntax.
- Simple imperative style consistent with existing modules.

### Global variable pattern (CRITICAL)
- All globals defined and initialized in `AHKeyMap.ahk` only.
- Modules declare them with `global VarName` at top of file (no re-initialization).
- Violating this causes silent overwrite at `#Include` time.

### Naming
- Functions: `PascalCase` (`LoadAllConfigs`, `ReloadAllHotkeys`)
- Local variables: `camelCase` (`configName`, `procList`)
- Globals: `PascalCase` (`CurrentConfigName`, `AllConfigs`)
- Constants: `UPPER_SNAKE` (`APP_NAME`, `CONFIG_DIR`)

### Formatting
- Indent: 4 spaces (no tabs).
- Strings: double quotes (`"`).
- Section headers: `; ============...` comment blocks.
- Keep line lengths reasonable; prefer clarity over compactness.

### Data structures
- `Map()` for key/value data (configs, mappings, registries).
- Arrays for ordered lists (configs, mappings, processes).
- Copy Map entries when duplicating config/mapping data.
- Coerce INI numeric values with `Integer()`.

### Error handling
- Guard filesystem access with `FileExist` / `DirExist`.
- Wrap `IniRead`, `IniWrite`, `Hotkey` in `try` blocks.
- Defensive checks on dynamic structures (`Type(hk) != "Map"`).
- User-facing errors: `MsgBox("message", APP_NAME, "Icon!")`.
- Always reset `HotIf()` after temporary use.
- Cancel timers/handlers on cleanup paths to avoid leaks.
- File writes that replace existing data must use atomic pattern
  (write to `.tmp` then `FileMove`); see `SaveConfig` for reference.

### GUI conventions
- Modal dialogs: use `CreateModalGui` / `DestroyModalGui` helpers.
- Keep event handlers short; extract logic into helper functions.
- UI strings are Chinese; keep wording consistent with existing labels.
- Update status via `UpdateStatusText()` after relevant state changes.

### Hotkey engine conventions
- Three registration paths: A (no modifier), B (intercept combo), C (passthrough combo).
- Process-scoped hotkeys use `HotIf` + `MakeProcessChecker` closures.
- Priority: include > exclude > global.
- Keep `AllProcessCheckers` references alive to prevent GC of closures.
- Clean up timers/handlers in `UnregisterAllHotkeys`.

### Config / INI conventions
- Each config: standalone `.ini` in `configs/`.
- `SaveConfig` uses atomic write: writes to `.tmp` first, then replaces original.
- INI sections: `[Meta]` then `[Mapping1]`, `[Mapping2]`, ...
- Mapping keys: `ModifierKey`, `SourceKey`, `TargetKey`, `HoldRepeat`,
  `RepeatDelay`, `RepeatInterval`, `PassthroughMod`.
- `_state.ini` sections: `[State]` (LastConfig) and `[EnabledConfigs]`.
- `ProcessMode` values: `global`, `include`, `exclude`.
- Process lists: `|`-separated in INI, converted to arrays in code.
- Use default values in `IniRead` for backward compatibility.

### Performance
- AHK is single-threaded; keep callbacks quick and non-blocking.
- Avoid heavy work inside hotkey callbacks; delegate when possible.
- Always clean state maps when reloading hotkeys.

## Agent workflow rules
- Read relevant module(s) **before** editing.
- Do not modify existing code without user permission.
- Avoid touching unrelated files or reformatting large regions.
- Keep edits minimal and aligned with existing patterns.
- Do not add new tooling unless user requests it.
- If you see unexpected local changes, stop and ask the user.
- If you add features or fix bugs, ask user about updating docs.
