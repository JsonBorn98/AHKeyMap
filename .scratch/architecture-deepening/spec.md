# Architecture deepening — spec

Source: `/improve-codebase-architecture` run of 2026-09-02. Subagent friction report: `C:\Users\lijso\Desktop\VibeCode\uv_temp\ahkey_report.md` (persistent copy). Visual report (disposable): `%TEMP%\architecture-review-20260902-001506.html`.

Six deepening candidates were ranked and **all six were grilled to a shared understanding**. Ticket 04 absorbs the deferred items noted in 01/02: `HotkeyRegErrors`/`HotkeyConflicts` output-by-global and the `Refresh*`/`UpdateStatusText` placement.

## Pattern established by this effort

A deep module in this repo is an AHK v2 `class` in its own file under `src/core/`, exposed as a lazy static singleton (`ClassName.Instance`) so no new script globals appear. Tests construct isolated instances with `ClassName()` instead of mirroring internals in `TestBase.ResetAppState`. The interface is the test surface: behavior is observed through `DispatchSendHook` capture plus deliberately-public read-only snapshots.

## Tickets

All six landed on branch `architecture-deepening` (PR #2), final version 2.9.8. Landed order: 06 (4e16b2e) → 01 (9087bc9) → 02 (e229f50) → 05 (6151882) → 03 (aa9332f) → 04 (4f592cc).

- `issues/01-deepen-path-c-engine.md` — Depends on: none. Land first.
- `issues/02-collapse-config-working-copy.md` — Depends on: 01 (soft).
- `issues/03-one-mapping-schema.md` — Depends on: 01 (soft), 02 (soft).
- `issues/04-rendering-seam.md` — Depends on: 01 (hard), 02 (hard), 03 (soft).
- `issues/05-keycapture-completion-adapter.md` — Depends on: 02 (soft).
- `issues/06-foreground-process-seam.md` — Depends on: none.

Each ticket carries a `Depends on:` line with the strength and reason — those edges are the task graph.

## Parallelism

Every ticket bumps the same two version lines in `src/AHKeyMap.ahk`, and several edit the same globals block and the test base's state reset — parallel branches are guaranteed small merge conflicts there regardless of the logical graph. Recommended execution: serial spine **01 → 02 → 03 → 04**, with **06** (and cautiously **05**) as a parallel side track. If run via `/implement-spec`, the Depends-on edges above define the frontier; treat soft edges as ordering preferences, not blockers.

Each ticket: single commit, patch version bump (`;@Ahk2Exe-SetVersion` + `APP_VERSION`), suites `unit,integration` then `all` green, plus the manual verification steps listed in the ticket.
