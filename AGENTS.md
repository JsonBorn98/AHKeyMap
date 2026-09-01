# AGENTS.md
Guidance for agentic coding in this repository.
Audience: coding agents working on AHKeyMap.

## Project snapshot
- Windows desktop key remapping tool.
- AutoHotkey v2 only (`#Requires AutoHotkey v2.0`).
- Entry point: `src/AHKeyMap.ahk`.
- Runtime data: `configs/*.ini` and `configs/_state.ini` (runtime-created, gitignored).
- `APP_ROOT` resolves to repo root in source mode or EXE dir in compiled mode.

## Sources of truth
- Read `docs/architecture.md` before non-trivial changes.
- Read `docs/bug-backlog.md` before bug-fix work.
- `CLAUDE.md` is a shorter companion; use this file as the main agent guide.

## Cursor / Copilot rules
- `.cursor/rules/`, `.cursorrules`, and `.github/copilot-instructions.md` do not exist.
- No extra Cursor or Copilot rules need merging.

## Repo map
```text
src/AHKeyMap.ahk           — globals, constants, #Include list, StartApp()
src/shared/Schema.ahk      — mapping/config record schema (static namespaces: construction, normalization, path rule)
src/core/Config.ahk        — pure config/state INI I/O and atomic writes
src/core/ConfigStore.ahk   — config working copy owner: AllConfigs, selection, mutation chokepoint, OnChanged slot
src/core/Localization.ahk  — `L(key, args*)`, `BuildEnPack()`, `BuildZhPack()`
src/core/PathCEngine.ahk   — Path C engine (sessions, routing, repeat timers, own hotkey registration)
src/core/HotkeyEngine.ahk  — Path A/B registration, conflicts, process checkers
src/core/KeyCapture.ahk    — key capture via polling + mouse hook
src/shared/Utils.ahk       — key formatting, process picker, auto-start helpers
src/ui/GuiMain.ahk         — main window, tray menu, modal helpers, render-from-state layer (pure view-model builders + widget writes)
src/ui/MappingEditor.ahk   — mapping edit dialog
src/ui/GuiEvents.ahk       — config/mapping CRUD and scope editing
tests/support/TestBase.ahk — assertions, sandbox reset, send capture
scripts/test.ps1           — PowerShell test runner
scripts/build.ps1          — compiler/package script
```

## Run / build / lint
```powershell
AutoHotkey64.exe src\AHKeyMap.ahk
build.bat
build.bat full
build.bat skiptests
pwsh ./scripts/build.ps1
```
- `build.bat` is the human entry point: Safe = `unit,integration`, Full = `all`, Quick = skip tests.
- `scripts/build.ps1` is the scripted entry; it auto-locates `Ahk2Exe` and the v2 base file.
- Artifacts go to `dist/`.
- No lint tool is configured. Do not invent lint/build tooling unless asked.

## Test commands
```powershell
pwsh ./scripts/test.ps1 -Suite all
pwsh ./scripts/test.ps1 -Suite unit,integration
pwsh ./scripts/test.ps1 -Suite unit
pwsh ./scripts/test.ps1 -Suite gui
```
- Suites: `unit`, `integration`, `gui`, `all` (`all` expands to all three suites).
- The runner discovers `tests/<suite>/**/*.test.ahk`; there is no `-TestFile` flag.

### Run a single test file
```powershell
AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\unit\scope_logic.test.ahk
```
- Set `AHKM_TEST_LOG_FILE=path.log` before launch for runner-style logs.
- Useful runner options: `-Ci`, `-OutputDir <dir>`, `-AutoHotkeyPath <exe>`.
- Artifacts: `test-results/summary.json`, `test-results/logs/`, `test-results/screenshots/`.
- `test.ps1` deletes `test-results/` on start, must not run concurrently, and `gui` must run exclusively.
- Manual verification is still needed for Path A/B/C behavior, RButton gestures, focus edges, and long-press timing.

## Test authoring
- Test files are standalone AHK processes that set `__AHKM_TEST_MODE := true`, point `__AHKM_CONFIG_DIR` at a temp `configs` directory, `#Include` `src/AHKeyMap.ahk`, then `#Include` `tests/support/TestBase.ahk`.
- `tests/support/TestBase.ahk` provides assertions, sandbox reset helpers, send capture, and suite logging.

## Versioning / release rules
- Any feature or bug fix must update both version declarations in `src/AHKeyMap.ahk`: `;@Ahk2Exe-SetVersion x.y.z` and `global APP_VERSION := "x.y.z"`.
- New features bump minor; bug fixes bump patch; release tags must be `vX.Y.Z` and match `APP_VERSION`.
- `.github/workflows/release.yml` publishes releases from matching tags.
- Only commit when the user explicitly asks; prefer English subjects like `feat: ...`, `fix: ...`, `docs: ...`.

## Include / import rules
- `src/AHKeyMap.ahk` owns the entire `#Include` list. Do not add cross-includes from leaf modules.
- Include order follows dependency flow:
  1. `shared/Schema.ahk`
  2. `core/Config.ahk`
  3. `core/ConfigStore.ahk`
  4. `shared/Utils.ahk`
  5. `core/Localization.ahk`
  6. `core/PathCEngine.ahk`
  7. `core/HotkeyEngine.ahk`
  8. `core/KeyCapture.ahk`
  9. `ui/GuiMain.ahk`
  10. `ui/MappingEditor.ahk`
  11. `ui/GuiEvents.ahk`
- Only `src/AHKeyMap.ahk` initializes globals with `:=`; other modules may declare `global VarName` but must not reinitialize shared state.

## Code style
### Language and structure
- AutoHotkey v2 syntax only; never use v1-style commands.
- Keep code imperative and close to existing module patterns.
- Prefer small helper functions over large GUI/event handlers.
- Keep edits narrow; do not refactor unrelated code.

### Naming and formatting
- Functions/globals: `PascalCase`; locals: `camelCase`; constants: `UPPER_SNAKE`.
- Test functions: `Test_DescriptiveName`; callbacks commonly use `On...` or `...Callback`.
- Use 4 spaces, no tabs; double-quoted strings only.
- Concatenate via space or `.=`; use positional `Format` args like `{1}` and `{2}`.
- Preserve banner headers, surrounding whitespace, and English source comments.

### Types and shared state
- Use `Map()` for keyed records and arrays for ordered collections.
- Mapping/config records are `Map()`-based and constructed through `src/shared/Schema.ahk` (`Mapping.Make`, `ConfigRecord.Make`); never restate the field list inline.
- `Mapping.Normalize` enforces the record invariants (7-key whitelist, integer coercion, defaults, min-10 repeat timing); `Mapping.ClassifyPath`/`Mapping.HotkeyStringFor` own the path rule and hotkey-string derivation; `Mapping.ToIniPairs` owns the serialization field list.
- Clone entries with `for k, v in old`, not direct assignment.
- Prefer in-place mutation (`.Length := 0`, `.Push(...)`) over replacing shared arrays/maps.
- Coerce numeric INI values with `Integer()` on load.
- Process lists are stored as `|`-delimited strings in INI and parsed into arrays in memory.
- Config files use `[Meta]` plus `[Mapping1]`, `[Mapping2]`, ...; `_state.ini` stores `LastConfig`, `UILanguage`, and `[EnabledConfigs]`.

### Error handling and persistence
- Guard file/dir operations with `FileExist` or `DirExist`.
- Wrap `IniRead`, `IniWrite`, `Hotkey`, and GUI operations in `try`.
- Use defensive checks such as `Type()`, `Has()`, and `HasOwnProp()`.
- User-visible failures should be localized via `MsgBox(L(...))`.
- Persist config/state atomically: write a `.tmp` file, then `FileMove(..., 1)`.
- Always call `HotIf()` after temporary `HotIf(callback)` scoping.
- Clean up timers, hotkeys, hooks, and modal state on failure paths.
- Config names must not contain `\ / : * ? " < > | = [ ]`.

### Localization and UI
- All UI strings go through `L(key, args*)`.
- Add new keys to both `BuildEnPack()` and `BuildZhPack()`.
- Default language on fresh install is English (`en-US`).
- Do not hardcode Chinese UI text in source files.
- Use `CreateModalGui` and `DestroyModalGui` for dialogs.

### Hotkey and scope conventions
- The engine uses three paths: Path A (no modifier), Path B (intercept combo), Path C (passthrough combo with session state).
- Path C lives in `src/core/PathCEngine.ahk`; production code uses the lazy singleton `PathCEngine.Instance`, and only its `Commit()`/`Reset()` methods touch `Hotkey()`.
- Process scope priority is `include > exclude > global`; an empty include/exclude list effectively behaves as global.
- Preserve Path C wheel-routing and `RButton` gesture behavior.
- Keep `AllProcessCheckers` references alive for closure lifetime.

### Config store conventions
- `src/core/ConfigStore.ahk` owns the config working copy: the `AllConfigs` array, the current selection (`ConfigStore.Instance.SelectedName`), and every mutation.
- Read the selected config via `ConfigStore.Instance.Selected()` / `SelectedMappings()`; never keep a mirrored set of `Current*` globals.
- Every mutation goes through one store method (`Select`, `SetEnabled`, `SetScope`, `AddMapping`, `ReplaceMapping`, `DeleteMapping`, `CreateConfig`, `CopyConfig`, `DeleteConfig`); each ends in the same chokepoint: atomic persist (`SaveConfig` + `SaveEnabledStates`) → `ReloadAllHotkeys()` → `OnChanged(reloadResult)`. `Select` is render-only and notifies with `""`.
- GUI handlers shrink to input validation plus one store call; they must not persist or reload on their own.
- `src/core/Config.ahk` is pure INI I/O; it owns no selection state and no render code.
- Tests reset the store with `ResetConfigStoreForTests()` (TestBase calls it from `ResetAppState`).

### Rendering seam conventions
- `ConfigStore.OnChanged` is the only core→ui data flow: core fires it, ui registers it. `BuildMainGui()` registers `RenderFromState` at startup; nothing in `src/core/` may reference GUI controls or ui functions.
- `RenderFromState(reloadResult)` in `src/ui/GuiMain.ahk` is the single render entry; it stores the reload result in the ui-owned `LastReloadResult` global and refreshes dropdown, scope controls, mapping list, and status bar.
- Rendering only runs when the main window exists (`RenderFromState` returns early headless); there are no `StatusText = ""`-style test guards.
- Pure view-model builders (`BuildStatusSummary`, `BuildMappingRows`, `BuildStatusDetails`, `FormatProcessDisplay`) take data and return view models; unit-test those, not the widgets. Widget writes stay in the thin `Refresh*`/`UpdateStatusText` functions.
- Engine output is returned, never stored in globals: `ReloadAllHotkeys()` returns `{conflicts, regErrors}`; `DetectHotkeyConflicts` and `PathCEngine.Commit()` return their arrays. `OnStatusTextClick` reads `LastReloadResult`.
- `StatusHasWarning` is written by the status render and read only by ui hover handlers.

## Common pitfalls
- `global Foo := value` inside a module overwrites the main-entry value at `#Include` time.
- Forgetting to reset `HotIf()` leaks scope to later hotkeys.
- `newMap := oldMap` copies a reference, not the contents.
- Direct overwrite instead of atomic write risks config corruption.
- Dropping Path B/C checker references can break scoped closures.

## Agent workflow
- Keep edits minimal and scoped.
- Do not add new tooling unless the user asks.
- If you see unexpected user changes, preserve them and ask before destructive edits.
- After feature/fix work, ask whether docs should be updated and whether a commit is desired.
