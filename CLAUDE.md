# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> See `AGENTS.md` for the full development spec and `docs/architecture.md` for in-depth design details.

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

All menu paths write artifacts to `dist/`.

For advanced or scripted build parameters, call `scripts/build.ps1` directly. It auto-locates `Ahk2Exe` and the v2 base file from Program Files, LocalAppData, or scoop.

### Lint / Tests
No lint tooling is configured.

Automated tests:
```
pwsh ./scripts/test.ps1 -Suite all
```

Fast non-GUI loop:
```
pwsh ./scripts/test.ps1 -Suite unit,integration
```

Current suites:
- `unit` — pure helpers, formatting, scope logic
- `integration` — config I/O, conflict detection, hotkey-engine state
- `gui` — in-process GUI smoke flow

Test artifacts:
- `test-results/logs` contains one detailed log per test file
- `test-results/summary.json` is the machine-readable run summary
- GUI failures may also produce screenshots under `test-results/screenshots`

Manual validation is still needed for true desktop input behavior:
- Exercise hotkey paths A/B/C against a real target app
- Confirm Path C `RButton` gesture / wheel behavior
- Check focus-switch timing edge cases and long-press repeat behavior
- Confirm `_state.ini` updates and no `.tmp` files remain after save

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

**Automated testing:**
- `scripts/test.ps1` discovers `tests/unit`, `tests/integration`, and `tests/gui`, then runs each `*.test.ahk` in its own AutoHotkey process and waits for the real exit code
- `tests/support/TestBase.ahk` provides assertions, sandbox setup, cleanup helpers, and direct per-test log writing via `AHKM_TEST_LOG_FILE`
- GUI failures may produce screenshots under `test-results/screenshots`

**Hotkey engine paths** (`HotkeyEngine.ahk`):
- **Path A** (`RegisterPathA`): no modifier → direct `Hotkey(source, callback)`
- **Path B** (`RegisterPathB`): modifier + `PassthroughMod=0` → `modKey & sourceKey` (intercepts modifier)
- **Path C** (`RegisterPathCMapping` + Path C engine): modifier + `PassthroughMod=1` → unified routing with `~modKey` passthrough and per-mod session state

**Process scope priority:** `include > exclude > global`

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

## Code Style

- **Language**: AutoHotkey v2.0+ only. No v1 syntax.
- **Naming**: `PascalCase` functions/globals, `camelCase` locals, `UPPER_SNAKE` constants.
- **Indent**: 4 spaces, no tabs. Strings use double quotes.
- **Data**: `Map()` for key/value, arrays for ordered lists.
- **File writes**: always use atomic pattern (write `.tmp` then `FileMove`); see `SaveConfig` and `SaveEnabledStates`.
- **HotIf**: always reset `HotIf()` after temporary use.
- **GUI**: use `CreateModalGui`/`DestroyModalGui` helpers; UI strings must be localized via `L(key, args*)` with entries in `BuildEnPack()` and `BuildZhPack()`. English is the default UI language on first run; Simplified Chinese is available via the tray language selector.
- **Error handling**: wrap `IniRead`, `IniWrite`, `Hotkey` in `try`; guard filesystem ops with `FileExist`/`DirExist`.
