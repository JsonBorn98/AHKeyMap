# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> See `AGENTS.md` for the full development spec and `docs/architecture.md` for in-depth design details.
> See `docs/bug-backlog.md` before bug-fix work — it tracks known issues with severity and fix direction.

## Commands

### Run (script mode)
```
AutoHotkey64.exe src\AHKeyMap.ahk
```
AutoHotkey v2 must be installed. Path to `AutoHotkey64.exe` depends on installation location.

### Build (compile to EXE)
```
build.bat
```
Without arguments, `build.bat` opens a 3-option menu for local Windows users:
- `Safe build` — run `unit,integration`, then build
- `Full build` — run `all`, then build
- `Quick build` — skip tests and build immediately

CLI modes (non-interactive): `build.bat full`, `build.bat skiptests`.

All menu/CLI paths write artifacts to `dist/`.

For advanced or scripted build parameters, call `scripts/build.ps1` directly. It auto-locates `Ahk2Exe` and the v2 base file from Program Files, LocalAppData, or scoop.

### Lint / Tests
No lint tooling is configured. Do not invent lint/build tooling unless asked.

Automated tests:
```
pwsh ./scripts/test.ps1 -Suite all
```

Fast non-GUI loop:
```
pwsh ./scripts/test.ps1 -Suite unit,integration
```

Run a single test file directly:
```
AutoHotkey64.exe /ErrorStdOut=UTF-8 tests\unit\scope_logic.test.ahk
```
Set `AHKM_TEST_LOG_FILE=path.log` before launch for runner-style per-file logs.

Current suites:
- `unit` — pure helpers, formatting, scope logic
- `integration` — config I/O, conflict detection, hotkey-engine state
- `gui` — in-process GUI smoke flow

Runner options: `-Ci` (keep running after failures), `-OutputDir <dir>` (custom output), `-AutoHotkeyPath <exe>` (override runtime).

Test artifacts land in `test-results/`: `logs/` (one per test file), `summary.json` (machine-readable), `screenshots/` (GUI failures only). The runner deletes `test-results/` on start.

### CI
`.github/workflows/ci.yml` runs on push/PR to `master`: validates version, runs all test suites, builds. Tag-driven releases via `.github/workflows/release.yml`.

## Architecture

Single-entry AHK v2 app. `src/AHKeyMap.ahk` initializes all globals and `#Include`s 8 modules in order:

```
src/core/Config.ahk → src/shared/Utils.ahk → src/core/Localization.ahk
  → src/core/HotkeyEngine.ahk → src/core/KeyCapture.ahk
  → src/ui/GuiMain.ahk → src/ui/MappingEditor.ahk → src/ui/GuiEvents.ahk
```

**Module responsibilities:**
- `Config.ahk` — load/save INI configs (atomic write via `.tmp`), enabled-state persistence (also atomic)
- `Localization.ahk` — in-memory language packs and `L(key, args*)`
- `HotkeyEngine.ahk` — hotkey register/unregister, three registration paths (A/B/C), cross-path B/C conflict detection
- `KeyCapture.ahk` — key capture (polling + mouse hook), 200ms startup delay, auto-cancel on focus loss
- `GuiMain.ahk` — window construction, tray menu, modal helpers
- `GuiEvents.ahk` — all GUI event handlers (CRUD, scope editing)
- `MappingEditor.ahk` — mapping edit dialog
- `Utils.ahk` — key display conversion, process picker, auto-start

**Hotkey engine paths** (`HotkeyEngine.ahk`):
- **Path A** (`RegisterPathA`): no modifier → direct `Hotkey(source, callback)`
- **Path B** (`RegisterPathB`): modifier + `PassthroughMod=0` → `modKey & sourceKey` (intercepts modifier)
- **Path C** (`RegisterPathCMapping` + Path C engine): modifier + `PassthroughMod=1` → unified routing with `~modKey` passthrough and per-mod session state

**Process scope priority:** `include > exclude > global`

**Test isolation:** Tests set `__AHKM_TEST_MODE := true` (skips `StartApp()`) and `__AHKM_CONFIG_DIR` (redirects config to temp dir). `tests/support/TestBase.ahk` provides assertions (`AssertTrue`, `AssertFalse`, `AssertEq`, `AssertMapHas`, `AssertFileExists`), sandbox helpers (`MakeMapping`, `BuildConfigRecord`, `SeedConfigFile`, `ResetTestSandbox`), and `EnableSendCapture()` for intercepting `Send()` calls via `DispatchSendHook`.

**Test authoring pattern:**
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

## Critical Rules

### Versioning — MUST update both on every change
- `src/AHKeyMap.ahk`: `;@Ahk2Exe-SetVersion x.y.z`
- `src/AHKeyMap.ahk`: `global APP_VERSION := "x.y.z"`

Rules: new features bump **minor**, bug fixes bump **patch**. Both values must match.

### Global variable pattern
- **Only `src/AHKeyMap.ahk`** initializes globals (`:=`).
- All modules declare with `global VarName` only — no re-initialization. Re-assigning in a module silently overwrites the main entry value at `#Include` time.

### Commit & release conventions
- Only commit when the user explicitly asks.
- Commit messages must be **English-first**, to keep Git history and GitHub Releases readable for a wider audience:
  - Use subjects like `feat: add bilingual UI`, `fix: prevent stale state keys`, `docs: rewrite README in English`.
  - If the user explicitly wants Chinese context, append it after the English subject instead of replacing it.
- Release titles and notes should be written in English. When editing release bodies manually, keep the primary description in English; optional Chinese notes can follow if needed.
- The repository has a tag-driven release workflow (`.github/workflows/release.yml`) that runs on `push` tags matching `v*.*.*`. After bumping the version in `src/AHKeyMap.ahk` and committing, you should:
  - Create an annotated tag `vX.Y.Z` that matches the `APP_VERSION` and `;@Ahk2Exe-SetVersion` values.
  - Push the tag so that GitHub Actions can build and publish the release artifacts.

### Config name restrictions
Config names must not contain `\ / : * ? " < > | = [ ]` — these break INI key names or filesystem paths.

## Common Pitfalls

- **Global reinit**: `global Foo := value` in a module silently overwrites the main entry value at `#Include` time. Use `global Foo` (declare only).
- **HotIf leak**: Forgetting to call `HotIf()` after `HotIf(callback)` scopes all subsequent hotkeys to that callback.
- **Map reference**: `newMap := oldMap` copies the reference. Clone with `for k, v in old → new[k] := v`.
- **Atomic write skip**: Always write to `.tmp` then `FileMove`; direct overwrite can corrupt on crash.
- **Closure lifetime**: Keep `AllProcessCheckers` references alive for Path B/C closure lifetime.

## Code Style

- **Language**: AutoHotkey v2.0+ only. No v1 syntax.
- **Naming**: `PascalCase` functions/globals, `camelCase` locals, `UPPER_SNAKE` constants.
- **Indent**: 4 spaces, no tabs. Strings use double quotes.
- **Data**: `Map()` for key/value, arrays for ordered lists.
- **File writes**: always use atomic pattern (write `.tmp` then `FileMove`); see `SaveConfig` and `SaveEnabledStates`.
- **HotIf**: always reset `HotIf()` after temporary use.
- **GUI**: use `CreateModalGui`/`DestroyModalGui` helpers; UI strings must be localized via `L(key, args*)` with entries in `BuildEnPack()` and `BuildZhPack()`. English is the default UI language on first run; Simplified Chinese is available via the tray language selector.
- **Error handling**: wrap `IniRead`, `IniWrite`, `Hotkey` in `try`; guard filesystem ops with `FileExist`/`DirExist`.
- **Test functions**: `Test_DescriptiveName` (e.g. `Test_ScopesOverlap_CoversPriorityCases`).
- **Comments**: English only in source. File headers use banner-style `; ==== ... ====` blocks.
