# AGENTS.md
Guidance for agentic coding in this repository.
Audience: coding agents working on AHKeyMap.
## Project snapshot
- Windows desktop key remapping tool.
- Language: AutoHotkey v2 only (`#Requires AutoHotkey v2.0`).
- Entry point: `src/AHKeyMap.ahk`.
- Runtime data: `configs/*.ini` and `configs/_state.ini` (created at runtime, gitignored).
- Also see `CLAUDE.md` for a shorter quick-reference.
## Sources of truth
- Read `docs/architecture.md` before non-trivial changes.
- Read `docs/bug-backlog.md` before bug-fix work.
- Use this root `AGENTS.md` as the operational guide.
## Cursor / Copilot rules
- `.cursor/rules/`, `.cursorrules`, `.github/copilot-instructions.md` — none exist.
- No extra Cursor or GitHub Copilot instructions need merging.
## Repo map
```
src/AHKeyMap.ahk           — globals, constants, #Include list, StartApp()
src/core/Config.ahk        — config/state INI I/O (atomic writes)
src/core/Localization.ahk  — L(key, args*) and en-US / zh-CN packs
src/core/HotkeyEngine.ahk  — three-path hotkey registration (A/B/C), conflict detection
src/core/KeyCapture.ahk    — key capture (polling + mouse hook)
src/shared/Utils.ahk       — key formatting, process picker, auto-start helpers
src/ui/GuiMain.ahk         — main window, tray menu, modal helpers
src/ui/MappingEditor.ahk   — mapping edit dialog
src/ui/GuiEvents.ahk       — GUI event handlers (config/mapping CRUD)
tests/support/TestBase.ahk — assertions, sandbox reset, send capture
scripts/test.ps1           — test runner (PowerShell 7+)
scripts/build.ps1          — compiler/package script
```
## Build commands
```powershell
build.bat                # Interactive menu: Safe / Full / Quick
build.bat full           # Run ALL tests, then build
build.bat skiptests      # Skip tests, build only
pwsh ./scripts/build.ps1 # Direct build (auto-locates Ahk2Exe)
AutoHotkey64.exe src\AHKeyMap.ahk  # Run from source
```
## Lint / static checks
- No lint tool is configured. Do not invent lint/build tooling unless asked.
- Verify with focused code reading, targeted tests, and diagnostics.
## Test commands
```powershell
pwsh ./scripts/test.ps1 -Suite all              # Full regression
pwsh ./scripts/test.ps1 -Suite unit,integration  # Fast local loop
pwsh ./scripts/test.ps1 -Suite unit              # Single suite
```
### Run a single test file
The runner has no `-TestFile` flag. Run the file directly:
```powershell
AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\unit\scope_logic.test.ahk
```
Set `AHKM_TEST_LOG_FILE=path.log` before launch for runner-style per-file logs.
### Runner options
- `-Ci` — keep running after failures (don't stop on first).
- `-OutputDir <dir>` — avoid deleting default `test-results/`.
- `-AutoHotkeyPath <exe>` — override runtime location.
### Test artifacts
- `test-results/summary.json` — machine-readable run summary.
- `test-results/logs/` — one log per test file (`START`/`PASS`/`FAIL` lines).
- `test-results/screenshots/` — captured only on GUI test failures.
## Test execution constraints
- Never run `test.ps1` concurrently in the same worktree.
- The runner deletes `test-results/` on start; `gui` tests must run exclusively.
- Manual verification still needed: real-app Path A/B/C, RButton gestures, focus edges, long-press timing.
## Test authoring
```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force
global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"
#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"
RegisterTest("description", Test_FunctionName)
RunRegisteredTests()
Test_FunctionName() {
    AssertEq(expected, actual)
}
```
- Assertions: `AssertTrue`, `AssertFalse`, `AssertEq`, `AssertNotEq`, `AssertMapHas`, `AssertMapNotHas`, `AssertFileExists`, `AssertContains`, `AssertArrayContains`, `AssertArrayNotContains`, `AssertThrows`.
- Helpers: `MakeMapping(...)`, `BuildConfigRecord(...)`, `SeedConfigFile(...)`, `EnableSendCapture()`.
- Each test runs in an isolated temp config dir; `ResetTestSandbox()` runs between tests.
## CI / CD
- `.github/workflows/ci.yml` — runs on push/PR to `master`; validates version, then runs unit/integration/gui suites in parallel, then builds. Toolchain is cached via `actions/cache@v4`. Each job has a `timeout-minutes: 10` guard. A `test-summary` job generates a Markdown results table in GitHub Step Summary.
- `.github/workflows/release.yml` — triggered by `v*.*.*` tags; validates tag matches `APP_VERSION`, builds, publishes GitHub Release.
- CI uses `scripts/download-github-toolchain.ps1` to fetch AutoHotkey v2 + Ahk2Exe.
## Versioning / release rules
- Every feature or bug fix must update **both** version declarations in `src/AHKeyMap.ahk`:
  `;@Ahk2Exe-SetVersion x.y.z` and `global APP_VERSION := "x.y.z"`.
- New features bump minor; bug fixes bump patch. The two values must always match.
- Only commit when the user explicitly asks.
- Commit messages: English conventional subjects — `feat: ...`, `fix: ...`, `docs: ...`.
- Release tags: `vX.Y.Z` matching `APP_VERSION`.
## Include / import rules
- `src/AHKeyMap.ahk` owns the `#Include` list. Do not add includes from leaf modules.
- Include order follows dependency flow:
  1. `core/Config.ahk` 2. `shared/Utils.ahk` 3. `core/Localization.ahk`
  4. `core/HotkeyEngine.ahk` 5. `core/KeyCapture.ahk`
  6. `ui/GuiMain.ahk` 7. `ui/MappingEditor.ahk` 8. `ui/GuiEvents.ahk`
## Code style
### Language and structure
- AutoHotkey v2 syntax only; never v1-style commands.
- Keep code imperative, close to existing module patterns.
- Prefer small helper functions over long event handlers.
- Keep edits scoped; do not refactor unrelated code.
### Naming
- Functions and globals: `PascalCase`. Locals: `camelCase`. Constants: `UPPER_SNAKE`.
- Test functions: `Test_DescriptiveName` (e.g. `Test_ScopesOverlap_CoversPriorityCases`).
- Callback suffix conventions: `OnConfigSelect`, `SendKeyCallback`, `HoldDownCallback`.
### Formatting
- Indent with 4 spaces; no tabs.
- Double-quoted strings only (`"..."`).
- String concatenation via space or `.=`; positional format args `{1}`, `{2}`.
- Keep lines readable; preserve surrounding whitespace/comment style.
### Comments
- English only in source (Chinese acceptable in agent discussion).
- File headers: banner-style `; ==== ... ====` blocks.
- Function-level: one-line `; Description` above the function.
- Preserve existing banner section separators.
### Types and shared state
- `Map()` for keyed records; arrays for ordered collections; object literals for simple records.
- Config records and mappings are Map-based — copy entries when duplicating (`for k, v in m`).
- Coerce numeric INI values with `Integer()` on load.
- **Only `src/AHKeyMap.ahk`** initializes globals (`:=`). Other modules declare `global VarName` but must not reinitialize.
- Prefer in-place mutation (`.Length := 0`, `.Push(...)`) over replacing shared arrays/maps.
### Error handling and persistence
- Guard file/dir ops with `FileExist` / `DirExist`.
- Wrap `IniRead`, `IniWrite`, `Hotkey`, GUI ops in `try` blocks.
- Defensive checks: `Type(x)`, `Has()`, `HasOwnProp()`.
- User-visible failures: localized `MsgBox(L(...))`.
- Always restore `HotIf()` after temporary scoped registration.
- Clean up timers, hotkeys, hooks, and modal state on failure paths.
- Atomic writes for config/state: write `.tmp`, then `FileMove(tmp, target, 1)`.
- Config files: `[Meta]` + `[Mapping1]`, `[Mapping2]`, ... sections.
- `_state.ini`: `LastConfig`, `UILanguage`, `[EnabledConfigs]` flags.
- Process lists: `|`-delimited strings parsed into arrays.
### Localization
- All UI strings go through `L(key, args*)`.
- Add new strings to **both** `BuildEnPack()` and `BuildZhPack()`.
- Default language on fresh install: English (`en-US`).
- Never hardcode Chinese UI strings in source.
- Use `CreateModalGui`/`DestroyModalGui` helpers for dialogs.
### Hotkey conventions
- Three-path model: Path A (no modifier), Path B (intercept combo), Path C (passthrough combo with session state).
- Keep `AllProcessCheckers` references alive for closure lifetime.
- Process scope priority: `include > exclude > global`; empty list = global.
- Preserve Path C RButton gesture and wheel handling behavior.
## Common pitfalls
- **Global reinit**: `global Foo := value` in a module silently overwrites the main entry value at `#Include` time. Use `global Foo` (declare only).
- **HotIf leak**: Forgetting to call `HotIf()` after `HotIf(callback)` scopes all subsequent hotkeys to that callback.
- **Map reference**: `newMap := oldMap` copies the reference. Clone with `for k, v in old → new[k] := v`.
- **Atomic write skip**: Always write to `.tmp` then `FileMove`; direct overwrite can corrupt on crash.
## Agent workflow
- Keep edits minimal and scoped. Do not touch unrelated files.
- Do not add new tooling unless requested.
- If you encounter unexpected local changes, stop and ask.
- After feature/fix work, ask whether docs should be updated and whether a commit is desired.
