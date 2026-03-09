# BUG_BACKLOG

Pending issues that are intentionally deferred. Read this file before starting new bug-fix tasks.

## BK-001
- Priority: P2
- Status: Resolved (2026-03-09)
- Title: `include` conflict detection misses real overlaps across scope combinations
- Location: `lib/HotkeyEngine.ahk` (`DetectHotkeyConflicts` / `ScopesOverlap`)
- Symptom: Conflict detection was incomplete for `include` combinations (e.g., include+global, include+exclude partial overlap) and could miss effective same-hotkey overlap.
- Fix summary:
  - Canonicalized process lists for include/exclude scopes (trim, dedupe, lowercase, sort).
  - Refactored scope overlap logic to intersection-based rules.
  - Added explicit helpers for `include/include` and `include/exclude` overlap checks.
- Current rule: If two mappings can both become active under any process context, they are treated as overlapping and reported as conflict.

## BK-002
- Priority: P3
- Status: Resolved (2026-03-09)
- Title: Deleted config not synced out of `_state.ini`
- Location: `lib/GuiEvents.ahk` (`OnDeleteConfig`)
- Symptom: After deleting a config, stale keys could remain in `_state.ini` until later.
- Fix summary: `OnDeleteConfig` now calls `SaveEnabledStates()` immediately after successful delete/removal from `AllConfigs`.

## BK-003
- Priority: P3
- Status: Resolved (2026-03-09)
- Title: Local/global mismatch risk when clearing `Mappings` in no-config branch
- Location: `lib/Config.ahk` (`RefreshConfigList` no-config branch)
- Symptom: `Mappings := []` without `global` could create a local variable in AHK v2 function scope.
- Fix summary: Changed to `global Mappings := []` in the no-config branch to guarantee clearing shared state.
