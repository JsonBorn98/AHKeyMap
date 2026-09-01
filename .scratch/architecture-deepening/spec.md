# Architecture deepening — spec

Source: `/improve-codebase-architecture` run of 2026-09-02. Subagent friction report: `C:\Users\lijso\Desktop\VibeCode\uv_temp\ahkey_report.md` (persistent copy). Visual report (disposable): `%TEMP%\architecture-review-20260902-001506.html`.

Six deepening candidates were ranked and **all six were grilled to a shared understanding**. Ticket 04 absorbs the deferred items noted in 01/02: `HotkeyRegErrors`/`HotkeyConflicts` output-by-global and the `Refresh*`/`UpdateStatusText` placement.

## Pattern established by this effort

A deep module in this repo is an AHK v2 `class` in its own file under `src/core/`, exposed as a lazy static singleton (`ClassName.Instance`) so no new script globals appear. Tests construct isolated instances with `ClassName()` instead of mirroring internals in `TestBase.ResetAppState`. The interface is the test surface: behavior is observed through `DispatchSendHook` capture plus deliberately-public read-only snapshots.

## Tickets

- `issues/01-deepen-path-c-engine.md` — land first. Touches `ReloadAllHotkeys` skeleton.
- `issues/02-collapse-config-working-copy.md` — land after 01 (shares the `ReloadAllHotkeys` seam).
- `issues/03-one-mapping-schema.md` — land after 01+02 (all three touch `HotkeyEngine.ahk` and the test base).
- `issues/04-rendering-seam.md` — land after 01-03 (render reads store state; engine output becomes return values).
- `issues/05-keycapture-completion-adapter.md` — land after 02 (both touch `MappingEditor.ahk`); otherwise independent.
- `issues/06-foreground-process-seam.md` — zero dependencies; land any time.

Each ticket: single commit, patch version bump (`;@Ahk2Exe-SetVersion` + `APP_VERSION`), suites `unit,integration` then `all` green, plus the manual verification steps listed in the ticket.
