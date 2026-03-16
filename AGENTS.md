# AGENTS.md
Guidance for agentic coding in this repository.
Audience: coding agents working on AHKeyMap.
## Project snapshot
- Windows desktop key remapping tool.
- Language: AutoHotkey v2 only.
- Entry point: `src/AHKeyMap.ahk`.
- Runtime data: `configs/*.ini` and `configs/_state.ini`.
## Sources of truth
- Read `docs/architecture.md` before non-trivial changes.
- Read `docs/bug-backlog.md` before bug-fix work.
- Use this root `AGENTS.md` as the operational guide.
## Cursor / Copilot rules
- `.cursor/rules/` does not exist.
- `.cursorrules` does not exist.
- `.github/copilot-instructions.md` does not exist.
- No extra Cursor or GitHub Copilot instructions need merging.
## Repo map
- `src/AHKeyMap.ahk` — globals, constants, include list, startup.
- `src/core/Config.ahk`, `src/core/Localization.ahk` — config/state and localization.
- `src/core/HotkeyEngine.ahk`, `src/core/KeyCapture.ahk` — hotkey engine and input capture.
- `src/shared/Utils.ahk` — key formatting, process picker, auto-start helpers.
- `src/ui/GuiMain.ahk`, `src/ui/MappingEditor.ahk`, `src/ui/GuiEvents.ahk` — GUI construction and events.
- `tests/support/TestBase.ahk` — assertions, sandbox reset, send capture.
- `scripts/test.ps1` — test runner; `scripts/build.ps1` — compiler/package script.
## Build commands
### Interactive/local entrypoint
```powershell
build.bat
```
- `Safe build` → run `unit,integration`, then build.
- `Full build` → run `all`, then build.
- `Quick build` → skip tests, build immediately.
### Non-interactive shortcuts
```powershell
build.bat full
build.bat skiptests
```
### Direct build script
```powershell
pwsh ./scripts/build.ps1
pwsh ./scripts/build.ps1 -OutputDir dist
pwsh ./scripts/build.ps1 -Ahk2ExePath "C:\path\Ahk2Exe.exe" -BaseFilePath "C:\path\AutoHotkey64.exe"
```
### Run from source
```powershell
AutoHotkey64.exe src\AHKeyMap.ahk
```
## Lint / static checks
- No lint tool is configured.
- Do not invent lint/build tooling unless the user asks.
- Verify with focused code reading, targeted tests, and diagnostics.
## Test commands
### Full regression
```powershell
pwsh ./scripts/test.ps1 -Suite all
```
### Fast local loop
```powershell
pwsh ./scripts/test.ps1 -Suite unit,integration
```
### Run one suite
```powershell
pwsh ./scripts/test.ps1 -Suite unit
pwsh ./scripts/test.ps1 -Suite integration
pwsh ./scripts/test.ps1 -Suite gui
```
### Run a single test file
The PowerShell runner has **no** `-TestFile` option.
Run the test file directly with AutoHotkey:
```powershell
AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\unit\scope_logic.test.ahk
AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\integration\config_io.test.ahk
AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\gui\main_smoke.test.ahk
```
- For runner-style per-file logs, set `AHKM_TEST_LOG_FILE` before launch.
### Useful runner options
```powershell
pwsh ./scripts/test.ps1 -Suite unit -Ci
pwsh ./scripts/test.ps1 -Suite unit -OutputDir test-results-unit
pwsh ./scripts/test.ps1 -Suite unit -AutoHotkeyPath "C:\path\AutoHotkey64.exe"
```
- `-Ci` keeps running after failures; `-OutputDir` avoids deleting the default `test-results/` folder.
## Test execution constraints
- Do not run multiple `pwsh ./scripts/test.ps1 ...` commands concurrently in one worktree.
- The runner deletes `test-results/` at the start unless `-OutputDir` is used; `gui` tests must run exclusively.
- Outputs: `test-results/summary.json`, `test-results/logs/`, `test-results/screenshots/`.
- Manual verification is still needed for real-app Path A/B/C behavior, Path C `RButton` gestures, focus/process-scope edges, and long-press repeat timing.
## Versioning / release rules
- Every feature or bug fix must update both version declarations in `src/AHKeyMap.ahk`: `;@Ahk2Exe-SetVersion x.y.z` and `global APP_VERSION := "x.y.z"`.
- New features bump the minor version; bug fixes bump the patch version.
- The two version values must always match.
- Only commit when the user explicitly asks.
- Prefer English conventional subjects such as `feat: ...`, `fix: ...`, `docs: ...`.
- If the user asks for a release tag, create `vX.Y.Z` matching `APP_VERSION`.
## Include / import rules
- `src/AHKeyMap.ahk` owns the `#Include` list.
- Do not add `#Include` lines from leaf modules.
- Keep include order aligned with dependency flow:
  1. `core/Config.ahk`
  2. `shared/Utils.ahk`
  3. `core/Localization.ahk`
  4. `core/HotkeyEngine.ahk`
  5. `core/KeyCapture.ahk`
  6. `ui/GuiMain.ahk`
  7. `ui/MappingEditor.ahk`
  8. `ui/GuiEvents.ahk`
- Add new modules only from `src/AHKeyMap.ahk`.
## Code style
### Language and structure
- Use AutoHotkey v2 syntax only; never write v1-style commands.
- Keep code imperative and close to existing module patterns.
- Prefer small helper functions over long event handlers.
- Keep edits scoped; do not refactor unrelated code opportunistically.
### Comments and documentation
- Write code, identifiers, comments, and new technical docs in English.
- Chinese is acceptable in agent discussion, not as repository source text.
- Preserve existing banner-style section comments.
### Naming and formatting
- Functions and globals: `PascalCase`; locals: `camelCase`; constants: `UPPER_SNAKE`.
- Test functions: `Test_DescriptiveName`.
- Indent with 4 spaces and use double-quoted strings.
- Keep lines readable; do not compress logic for brevity.
- Preserve surrounding whitespace/comment style instead of reformatting large blocks.
### Types and shared state
- Use `Map()` for keyed records and registries; arrays for ordered collections.
- Config records and mappings are Map-based.
- Copy mapping/config entries when duplicating them.
- Coerce numeric INI values with `Integer()` when loading.
- Define and initialize globals only in `src/AHKeyMap.ahk`.
- Other modules may declare `global VarName` but must not reinitialize shared globals.
- Prefer in-place mutation over replacing shared arrays/maps.
### Error handling and persistence
- Guard file and directory access with `FileExist` / `DirExist` where appropriate.
- Wrap `IniRead`, `IniWrite`, `Hotkey`, and fragile GUI operations in `try` blocks.
- Prefer defensive checks on dynamic objects, e.g. `Type(x)`, `Has()`, `HasOwnProp()`.
- User-visible failures should use localized `MsgBox(...)` text.
- Clean up timers, hotkeys, hooks, and modal state on failure paths.
- Always restore `HotIf()` after temporary scoped registration.
- Preserve the atomic write pattern for config/state writes: write `.tmp`, then replace.
- Config files use `[Meta]`, `[Mapping1]`, `[Mapping2]`, ... sections.
- `_state.ini` stores `LastConfig`, `UILanguage`, and enabled-state flags.
- Process lists are stored as `|`-delimited strings and parsed into arrays.
### Localization and hotkey conventions
- All user-facing UI strings must go through `L(key, args*)`.
- Add new strings to both `BuildEnPack()` and `BuildZhPack()`.
- Default UI language on fresh install is English (`en-US`).
- Do not hardcode Chinese UI strings in AHK source.
- Use modal helpers from `GuiMain.ahk` for dialogs.
- Respect the three-path model: Path A = no modifier; Path B = intercept combo; Path C = passthrough combo with session state.
- Keep `AllProcessCheckers` references alive for closure lifetime.
- Empty include/exclude lists behave as global scope; priority is `include > exclude > global`.
- Preserve Path C behavior for `RButton` gestures and wheel handling.
## Agent workflow expectations
- Keep edits minimal and scoped.
- Do not touch unrelated files.
- Do not add new tooling unless requested.
- If you encounter unexpected local changes, stop and ask.
- After feature/fix work, ask whether docs should be updated and whether a commit is desired.
