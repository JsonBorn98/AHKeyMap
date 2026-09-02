# 01 — Deepen the Path C engine

Status: resolved

Depends on: none — land first; tickets 03/04 rewire the shapes this one creates, so every other ticket assumes it exists.

## Problem

Path C (passthrough modifier combos) is a shallow module: its interface is five globals (`PathCMappingByModSource`, `PathCModSessions`, `PathCModsUsed`, `PathCSourceKeysUsed`, `PathCWheelRoutePredicates`), a `HoldTimers` map shared with Path A/B, `RepeatTimerCallback`'s optional `modKey` mode flag, string state literals scattered across six callbacks, and an ordering invariant (`RegisterPathCMapping` must complete before `RegisterAllPathCHotkeys`) that lives nowhere. Four regressions each leaked a different piece of this interface: BUG-004 (long-press stop), BUG-009/013 (raw-key fallback re-entrancy), BUG-015 (RButton menu dismissal), BUG-016 (wheel routing). Tests reach past the interface and hand-craft session objects.

## Decisions (grilled 2026-09-02, all confirmed)

1. **Class module**: `class PathCEngine` in a new file `src/core/PathCEngine.ahk`. Include it in `src/AHKeyMap.ahk` after `core/Localization.ahk` and before `core/HotkeyEngine.ahk` (it depends on `Utils.ahk` `DispatchSend`/`KeyToSendFormat`; `HotkeyEngine` depends on it). Update the repo map and include-order list in `AGENTS.md`.
2. **Singleton access**: lazy static `PathCEngine.Instance`. Zero new script globals. Tests build isolated instances with `PathCEngine()` and stop mirroring Path C state in `TestBase.ResetAppState`.
3. **Engine owns registration**: it makes its own `Hotkey()`/`HotIf()` calls, holds its own registration records and the wheel-route predicate references, and disables them in `Reset()`. The two-phase build becomes `AddMapping(...)` during the config loop + `Commit()` after it, so the old ordering invariant disappears structurally (only `Commit` touches `Hotkey()`).
4. **Engine owns its repeat timers**: Path C repeat logic (`PathC_StartRepeat` + the modifier-still-held check) moves in; `HoldTimers`/`StopHoldTimer`/`StartRepeat`/`RepeatTimerCallback` serve Path A/B only, and `RepeatTimerCallback` loses its optional `modKey` parameter.
5. **Interface is the test surface**: behavioral tests via public methods + `DispatchSendHook`, plus one deliberately-public read-only snapshot `GetSessionState(modKey)`.

## Public interface (the whole surface, 9 members)

```
PathCEngine.Instance.AddMapping(mapping, id, configName, checker)  ; was RegisterPathCMapping
PathCEngine.Instance.Commit()                                      ; was RegisterAllPathCHotkeys
PathCEngine.Instance.Reset()                                       ; Path C part of UnregisterAllHotkeys
PathCEngine.Instance.OnModDown(modKey)
PathCEngine.Instance.OnModUp(modKey)
PathCEngine.Instance.OnSourceDown(sourceKey)
PathCEngine.Instance.OnSourceUp(sourceKey)
PathCEngine.Instance.ShouldRouteWheel(sourceKey)                   ; bound as HotIf predicate
PathCEngine.Instance.GetSessionState(modKey)                       ; read-only: "Idle" | "HeldNoCombo" | "GestureActive"
```

Internals: a `PathCSession` class whose constructor is the invariant (`state`, `isGesture`, `activeSources`, `repeatMappings`, plus `Reset()`), state names as `STATE_*` constants on `PathCEngine`, the scope-check logic of `PathC_IsMappingActive`, the raw-key fallback, and the RButton context-menu dismissal (`CONTEXT_MENU_DISMISS_DELAY` timer) all move inside.

## Changes by file

- `src/core/PathCEngine.ahk` — new; absorbs `HotkeyEngine.ahk:577-604` (`RegisterPathCMapping`), `:673-940` (all `PathC_*`), and the Path C clears at `:147-151`.
- `src/core/HotkeyEngine.ahk` — `RegisterMapping` Path C branch (:506-509) calls `AddMapping`; `ReloadAllHotkeys` (:205) calls `Commit()`; `UnregisterAllHotkeys` calls `Reset()` instead of clearing PathC globals; `RepeatTimerCallback` signature loses `modKey`. Engine keeps appending registration failures to the shared `HotkeyRegErrors` global (output-by-global cleanup belongs to candidate 4 — out of scope here).
- `src/AHKeyMap.ahk` — delete the five `PathC*` globals (:88-92); add the include; bump `;@Ahk2Exe-SetVersion` and `APP_VERSION` to `2.9.3`.
- `tests/support/TestBase.ahk` — delete the Path C mirror in `ResetAppState` (:138-142, :197-201).
- `tests/integration/hotkey_engine_state.test.ahk` — rewrite Path C cases against the public interface: drive `AddMapping`/callbacks on a fresh instance, assert via `DispatchSendHook` capture and `GetSessionState`. Replace registration-bookkeeping assertions on the deleted globals (`PathCMappingByModSource` etc. in `Test_ReloadAllHotkeys_TracksDispatchStateAndCleanup`) with behavior-level assertions.

## Acceptance

- `pwsh ./scripts/test.ps1 -Suite unit,integration` green, then `-Suite all` green.
- Behavior parity for the four historical regressions: wheel routing (BUG-016), raw-key fallback (BUG-009/013), long-press stop (BUG-004), RButton gesture + menu dismissal (BUG-015).
- Manual verification (per AGENTS.md): Path C combo triggering, wheel routing while a modifier session is active, RButton gestures, long-press repeat timing.
- Single commit, English subject (`refactor: deepen the Path C engine into a class module` or similar).

## Comments

> *This was generated by AI during triage.*

Landed in PR #2 (commit 9087bc9).

## Agent Brief

**Category:** enhancement
**Summary:** Consolidate the Path C passthrough-combo engine into one deep class module with a 9-member public interface.

**Current behavior:**
Path C state lives in five script globals plus a repeat-timer map shared with Path A/B. Sessions are anonymous objects with string state names scattered across six callbacks. Registration is two-phase and correct only by calling-order convention. The shared repeat callback carries an optional modifier parameter that switches between two behaviors. Tests construct and mutate session internals by hand. Four historical regressions (long-press stop, raw-key fallback re-entrancy, RButton menu dismissal, wheel routing) each leaked a different piece of this unwritten interface.

**Desired behavior:**
A `PathCEngine` class owns the session state machine, the mapping table, wheel routing, repeat timers, and its own hotkey registration. All Path C behavior is reachable only through the public interface: `AddMapping` / `Commit` / `Reset` / `OnModDown` / `OnModUp` / `OnSourceDown` / `OnSourceUp` / `ShouldRouteWheel` / `GetSessionState` (read-only). Sessions are instances of an internal session class with constructor-enforced shape and named state constants. No Path C script globals remain; tests build isolated engine instances and assert behavior through the send-capture hook plus `GetSessionState`. Path A/B behavior and their repeat timers are unchanged; the shared repeat callback loses its modifier mode flag. Hotkey registration errors are still reported through the existing shared mechanism (its cleanup is ticket 04).

**Key interfaces:**
- `PathCEngine`: new class module; production access via lazy static `PathCEngine.Instance`; tests construct fresh instances.
- Session state constants replace the `"Idle" / "HeldNoCombo" / "GestureActive"` string literals.
- The engine absorbs the modifier/source hotkey registration including wheel-route predicate lifetime.

**Acceptance criteria:**
- [ ] Unit + integration suites green, then the full suite green
- [ ] No `PathC*` script globals remain anywhere (declarations, module tops, test reset)
- [ ] Behavior parity: wheel routing, raw-key fallback, long-press stop, RButton gesture + menu dismissal
- [ ] Integration tests drive only the public interface (no hand-crafted session objects)
- [ ] Manual verification: Path C combos, wheel routing, RButton gestures, long-press repeat (maintainer step)

**Out of scope:**
- Path A/B behavior changes
- Engine output-by-global cleanup, render-function placement (ticket 04)
- Mapping schema / path-classification unification (ticket 03)
- `ConfigStore` working-copy collapse (ticket 02)
