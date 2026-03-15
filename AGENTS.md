# AGENTS.md

Guidance for agentic coding in this repository.
This is a Windows AutoHotkey v2 app with a modular AHK layout.

## Sources of truth
- Project architecture: `ARCHITECTURE.md`
- Deferred bugs backlog: `BUG_BACKLOG.md` (read before new bug-fix tasks)
- No Cursor rules or Copilot instructions are present in the repo.

## Repo map
- `AHKeyMap.ahk` (~181 lines) — main entry, global variable initialization, named constants, `#Include` list, startup
- `lib/Config.ahk` (~370 lines) — config load/save (atomic write), config list management, enabled state persistence
- `lib/Utils.ahk` (~222 lines) — key display conversion, process picker (with dedup), auto-start utilities
- `lib/Localization.ahk` (~300 lines) — localization packs and `L(key, args*)`
- `lib/HotkeyEngine.ahk` (~718 lines) — hotkey register/unregister, long-press repeat, modifier logic (paths A/B/C), conflict detection (including cross-path B/C), scope canonicalization
- `lib/KeyCapture.ahk` (~480 lines) — key capture mechanism (polling + mouse hook, auto-cancel on focus loss)
- `lib/GuiMain.ahk` (~161 lines) — main window construction (resize-adaptive layout), tray menu, modal window helpers
- `lib/MappingEditor.ahk` (~146 lines) — mapping edit dialog, key capture entry, repeat parameter validation
- `lib/GuiEvents.ahk` (~402 lines) — GUI event handlers (config CRUD, scope editing, config name validation)
- `tests/` — automated AHK test suites (`unit`, `integration`, `gui`, `manual-e2e`)
- `scripts/Test.ps1` — PowerShell test runner, suite discovery, log/screenshot/result collection
- `configs/` — runtime INI files (gitignored)
- `build.bat` — compile script for Ahk2Exe
- `.gitignore` — ignores `AHKeyMap.exe`, `configs/`, `dist/`, `test-results/`, `*.bak`, `*.tmp`, `.claude/`, `.cursor/`

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
Automated regression suite:
```
pwsh ./scripts/Test.ps1 -Suite all
```

Fast inner loop (non-GUI):
```
pwsh ./scripts/Test.ps1 -Suite unit,integration
```

Coverage today:
- `unit` — pure helpers, formatting, scope logic
- `integration` — config I/O, conflict detection, hotkey engine state
- `gui` — in-process GUI smoke flow for config CRUD and mapping edits

Manual validation is still required for true desktop end-to-end input scenarios:
- Exercise Hotkey paths A/B/C against a real target app
- Path C `RButton` + wheel / gesture behavior
- Focus-switch timing and include/exclude scope edge cases
- Long-press repeat start/stop behavior in real applications

## Versioning (MUST follow)
Every change must update version in **both** places:
- `AHKeyMap.ahk` line 13: `;@Ahk2Exe-SetVersion x.y.z`
- `AHKeyMap.ahk` line 21: `global APP_VERSION := "x.y.z"`

Rules: new features bump minor, bug fixes bump patch. Both values must match.

## Commit conventions
- Only commit when user explicitly asks.
- **Commit messages MUST be English-first**, so that GitHub releases and changelogs stay English:
  - Prefer conventional subjects like `feat: add path C gesture state`, `fix: handle state file errors`, `docs: update README for bilingual UI`.
  - Optional: you may append a short Chinese note after the English subject if the user asks, but the leading summary must be English.
- After each feature or fix, proactively ask the user whether to update
  documentation and create a git commit.

### GitHub releases and automation
- GitHub Release notes are generated from commit messages, PR titles and labels — keep these **English-first** for consistency.
- Tag format: `vX.Y.Z` (already enforced by CI); release titles remain English (e.g. `AHKeyMap v2.7.0`).
- If you edit release bodies or changelog text manually (via `gh release` or GitHub UI), use English descriptions; Chinese notes can be added as a secondary explanation if needed.
 - After the user approves a release-ready change (version bumped and committed), create and push a tag that matches the app version to trigger the `.github/workflows/release.yml` pipeline:
   - Tag name must be `vX.Y.Z` and must match `APP_VERSION` in `AHKeyMap.ahk`.
   - The tag should point at a commit that is reachable from `master` (as validated by the workflow).

## Include order and module boundaries
`AHKeyMap.ahk` owns the `#Include` list. Current order:
1. `lib/Config.ahk`
2. `lib/Utils.ahk`
3. `lib/Localization.ahk`
4. `lib/HotkeyEngine.ahk`
5. `lib/KeyCapture.ahk`
6. `lib/GuiMain.ahk`
7. `lib/MappingEditor.ahk`
8. `lib/GuiEvents.ahk`

Boundaries:
- GUI construction → `GuiMain.ahk`; event handlers → `GuiEvents.ahk`
- Hotkey registration/cleanup → `HotkeyEngine.ahk`
- New modules: add to `#Include` list in `AHKeyMap.ahk` only.

## Code style guidelines

### Language and runtime
- AutoHotkey v2.0+ only. No v1 syntax.
- Simple imperative style consistent with existing modules.
- **Source language:** Code, identifiers, comments and new documentation should default to English.
- **Localization:** User-facing UI strings must go through the localization layer (`L(key, args*)`) and provide at least English and Simplified Chinese variants. Do not hardcode Chinese labels directly in code.
  - Default UI language on a fresh install is English (`en-US`); do not infer startup language from OS locale.
  - Chinese UI text lives in the `BuildZhPack()` language pack and Chinese-facing docs (for example `README.zh-CN.md`, `BUG_BACKLOG.md`), not as inline literals in .ahk source.

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
- UI strings must be localized via `L(key, args*)` with entries in both `BuildEnPack()` and `BuildZhPack()`. English is the default UI language; Simplified Chinese is available via the tray language selector.
- Update status via `UpdateStatusText()` after relevant state changes.
- Status bar turns orange and becomes clickable when warnings exist
  (`HotkeyConflicts` or `HotkeyRegErrors` non-empty); click shows a MsgBox with details.

### Hotkey engine conventions
- Three registration paths: A (no modifier), B (intercept combo), C (passthrough combo).
- `ReloadConfigHotkeys(configName)` for single-config reload (currently delegates to full reload).
- Process-scoped hotkeys use `HotIf` + `MakeProcessChecker` closures.
- Empty include/exclude lists are treated as global scope.
- Priority: include > exclude > global.
- Keep `AllProcessCheckers` references alive to prevent GC of closures.
- Clean up timers/handlers in `UnregisterAllHotkeys`.
- Cross-path B/C modifier conflicts are detected when the same modifier key is
  used in both intercept and passthrough modes with overlapping scopes.
- `CanonicalizeProcessScope` normalizes process lists (trim, dedupe, lowercase, sort)
  before comparison; used for both conflict detection and scope grouping.
- `ScopesOverlap` uses intersection-based rules for include/include,
  include/exclude, and other scope pair combinations.

### Config / INI conventions
- Each config: standalone `.ini` in `configs/`.
- `SaveConfig` and `SaveEnabledStates` both use atomic write:
  writes to `.tmp` first, then replaces original.
- INI sections: `[Meta]` then `[Mapping1]`, `[Mapping2]`, ...
- Mapping keys: `ModifierKey`, `SourceKey`, `TargetKey`, `HoldRepeat`,
  `RepeatDelay`, `RepeatInterval`, `PassthroughMod`.
- `_state.ini` sections: `[State]` (LastConfig) and `[EnabledConfigs]`.
- `ProcessMode` values: `global`, `include`, `exclude`.
- Process lists: `|`-separated in INI, converted to arrays in code.
- Config names must not contain `\ / : * ? " < > | = [ ]`.
- Use default values in `IniRead` for backward compatibility.
- Deleting a config must call `SaveEnabledStates()` immediately to
  sync `_state.ini` (prevents stale keys).

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
