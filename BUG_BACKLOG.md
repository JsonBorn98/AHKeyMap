# BUG_BACKLOG

Pending issues that are intentionally deferred. Read this file before starting new bug-fix tasks.

## BK-001
- Priority: P2
- Status: Open
- Title: `include` conflict detection is order-sensitive for process lists
- Location: `lib/HotkeyEngine.ahk` (around `DetectHotkeyConflicts` / `ScopesOverlap`)
- Symptom: `a.exe|b.exe` and `b.exe|a.exe` are treated as different scopes, so same-hotkey conflicts may be missed.
- Expected: Include scopes with same process set should be recognized as overlapping regardless of order.
- Suggested fix: Canonicalize include process list before comparison (trim, dedupe, lowercase, sort).

## BK-002
- Priority: P3
- Status: Open
- Title: Deleted config is not immediately synced out of `_state.ini`
- Location: `lib/GuiEvents.ahk` (`OnDeleteConfig`)
- Symptom: After deleting a config, stale keys may remain in `_state.ini` until a later sync point.
- Expected: `_state.ini` should be updated immediately after delete.
- Suggested fix: Call `SaveEnabledStates()` right after successful delete flow.

## BK-003
- Priority: P3
- Status: Open
- Title: Potential local/global mismatch when clearing `Mappings` in no-config branch
- Location: `lib/Config.ahk` (`RefreshConfigList` no-config branch)
- Symptom: `Mappings := []` is assigned without `global`, which may create a local variable in AHK v2 function scope.
- Expected: Global `Mappings` should always be cleared in no-config state.
- Suggested fix: Change to `global Mappings := []` in that branch.
