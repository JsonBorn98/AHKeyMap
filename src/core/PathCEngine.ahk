; ============================================================================
; AHKeyMap - Path C engine module
; Owns the passthrough-combo state machine, unified event routing, repeat
; timers, wheel routing, and the hotkey registration for Path C mappings.
; ============================================================================

; Globals shared across modules
global CONTEXT_MENU_DISMISS_DELAY
global HotkeyRegErrors

; For Path C, only register Up hotkeys on source keys that support key-up
SupportsKeyUpHotkey(hotkeyName) {
    return !IsWheelSourceKey(hotkeyName)
}

IsWheelSourceKey(sourceKey) {
    baseKey := RegExReplace(sourceKey, "^[~*$+!#^]+", "")
    return RegExMatch(baseKey, "^Wheel")
}

; ============================================================================
; Path C session
; ============================================================================

; One session per modifier key press cycle; the constructor enforces the shape
class PathCSession {
    __New() {
        this.state := PathCEngine.STATE_IDLE
        this.isGesture := false
        this.activeSources := Map()
        this.repeatMappings := Map()
    }

    ; End-of-session cleanup: reset every field back to a fresh Idle session
    Reset() {
        this.state := PathCEngine.STATE_IDLE
        this.isGesture := false
        this.activeSources := Map()
        this.repeatMappings := Map()
    }
}

; ============================================================================
; Path C engine
; ============================================================================

; Deep module for Path C (passthrough modifier combos):
;   AddMapping(...) during the config loop, Commit() after it (only Commit
;   touches Hotkey()), Reset() to disable everything, and the On*/ShouldRoute*
;   callbacks drive the per-modifier session state machine.
; Production code uses the lazy singleton `PathCEngine.Instance`; tests may
; construct isolated `PathCEngine()` instances instead.
class PathCEngine {
    ; Session state names (replace scattered string literals)
    static STATE_IDLE := "Idle"
    static STATE_HELD_NO_COMBO := "HeldNoCombo"
    static STATE_GESTURE_ACTIVE := "GestureActive"

    static _instance := ""

    static Instance {
        get {
            if (PathCEngine._instance = "")
                PathCEngine._instance := PathCEngine()
            return PathCEngine._instance
        }
    }

    __New() {
        ; "modKey|sourceKey" -> array of mapping entries
        this.mappingByModSource := Map()
        ; modKey / sourceKey -> true (which routing hotkeys to register)
        this.modsUsed := Map()
        this.sourceKeysUsed := Map()
        ; modKey -> PathCSession (current press cycle state)
        this.sessions := Map()
        ; Registration records ({checker, key, keyUp}) owned by this engine
        this.registrations := []
        ; mapping.id -> {fn, startFn, interval, active} repeat timers
        this.repeatTimers := Map()
    }

    ; ------------------------------------------------------------------------
    ; Registration (two-phase: AddMapping during config loop, Commit after it)
    ; ------------------------------------------------------------------------

    ; Record one Path C mapping for unified routing (was RegisterPathCMapping)
    ; (local name avoids shadowing the Mapping class; AHK names are case-insensitive)
    AddMapping(m, id, configName, checker) {
        if (Mapping.ClassifyPath(m) != Mapping.PATH_C)
            return

        modKey := m["ModifierKey"]
        sourceKey := m["SourceKey"]

        key := modKey "|" sourceKey
        if !this.mappingByModSource.Has(key)
            this.mappingByModSource[key] := []

        ; The internal entry object is derived from the Map record in this
        ; one place (the engine never reads the raw record shape elsewhere)
        entry := {
            modKey: modKey,
            sourceKey: sourceKey,
            targetKey: m["TargetKey"],
            holdRepeat: m["HoldRepeat"],
            repeatDelay: m["RepeatDelay"],
            repeatInterval: m["RepeatInterval"],
            configName: configName,
            id: id,
            checker: checker
        }
        this.mappingByModSource[key].Push(entry)

        this.modsUsed[modKey] := true
        this.sourceKeysUsed[sourceKey] := true
    }

    ; Register all Path C modifier/source routing hotkeys (was RegisterAllPathCHotkeys)
    ; This is the only place where the engine touches Hotkey()
    Commit() {
        ; Modifiers: keyboard/mouse keys all use "~modKey" / "~modKey Up" to pass through events
        for modKey, _ in this.modsUsed {
            if (modKey = "")
                continue

            downHk := "~" modKey
            upHk := "~" modKey " Up"

            try {
                HotIf()
                Hotkey(downHk, ObjBindMethod(this, "OnModDown", modKey), "On")
                Hotkey(upHk, ObjBindMethod(this, "OnModUp", modKey), "On")
            } catch as e {
                HotkeyRegErrors.Push(downHk)
                continue
            }

            this.registrations.Push({ checker: "", key: downHk, keyUp: upHk })
        }

        ; Source keys: listen centrally and let Path C decide what to trigger
        for sourceKey, _ in this.sourceKeysUsed {
            if (sourceKey = "")
                continue

            sourceHotkey := SubStr(sourceKey, 1, 1) = "*" ? sourceKey : "*" sourceKey
            record := { checker: "", key: sourceHotkey, keyUp: "" }

            ; KeyDown
            if (IsWheelSourceKey(sourceKey)) {
                ; Wheel sources only route while a Path C session could match,
                ; so native semantics like browser Ctrl+Wheel stay intact
                wheelRoutePredicate := ObjBindMethod(this, "ShouldRouteWheel", sourceKey)
                try {
                    HotIf(wheelRoutePredicate)
                    Hotkey(sourceHotkey, ObjBindMethod(this, "OnSourceDown", sourceKey), "On")
                    record.checker := wheelRoutePredicate
                } catch as e {
                    HotkeyRegErrors.Push(sourceHotkey)
                }
            } else {
                try {
                    HotIf()
                    Hotkey(sourceHotkey, ObjBindMethod(this, "OnSourceDown", sourceKey), "On")
                } catch as e {
                    HotkeyRegErrors.Push(sourceHotkey)
                }
            }

            ; KeyUp: only for source keys that support Up hotkeys
            if (SupportsKeyUpHotkey(sourceHotkey)) {
                srcUpHotkey := sourceHotkey " Up"
                try {
                    HotIf()
                    Hotkey(srcUpHotkey, ObjBindMethod(this, "OnSourceUp", sourceKey), "On")
                    record.keyUp := srcUpHotkey
                } catch as e {
                    HotkeyRegErrors.Push(srcUpHotkey)
                }
            }
            this.registrations.Push(record)
        }

        HotIf()
    }

    ; Disable all engine-owned hotkeys, stop repeats, and clear all state
    Reset() {
        ; Stop all repeat timers owned by this engine
        timerIds := []
        for mappingId, _ in this.repeatTimers
            timerIds.Push(mappingId)
        for _, mappingId in timerIds
            this.StopMappingRepeat(mappingId)

        ; End all modifier sessions
        modKeys := []
        for modKey, _ in this.sessions
            modKeys.Push(modKey)
        for _, modKey in modKeys
            this.EndSession(modKey)

        ; Disable each hotkey from the engine's own records, ignoring cleanup errors
        for _, info in this.registrations {
            try {
                if (info.checker != "")
                    HotIf(info.checker)
                else
                    HotIf()

                if (info.key != "")
                    Hotkey(info.key, "Off")
                if (info.keyUp != "")
                    Hotkey(info.keyUp, "Off")
            } catch {
                continue
            }
        }
        HotIf()

        ; Clear registration and mapping state in place
        this.registrations.Length := 0
        ClearEngineMap(this.mappingByModSource)
        ClearEngineMap(this.modsUsed)
        ClearEngineMap(this.sourceKeysUsed)
    }

    ; ------------------------------------------------------------------------
    ; Session state machine (bound as routing hotkey callbacks)
    ; ------------------------------------------------------------------------

    ; Modifier-key down (shared entry point)
    OnModDown(modKey, *) {
        ; Force-end any unfinished session before starting a new one
        if (this.sessions.Has(modKey) && this.sessions[modKey].state != PathCEngine.STATE_IDLE)
            this.EndSession(modKey)

        session := this.GetSession(modKey)
        session.Reset()
        session.state := PathCEngine.STATE_HELD_NO_COMBO
    }

    ; Modifier-key up (shared entry point)
    OnModUp(modKey, *) {
        session := this.GetSession(modKey)
        if (session.state = PathCEngine.STATE_IDLE) {
            return
        }

        isGesture := session.isGesture

        ; For RButton, only dismiss a possible context menu if this session actually triggered a Path C gesture.
        ; Sending Escape keeps browser-style right-button gestures usable.
        if (modKey = "RButton" && isGesture) {
            SetTimer(ObjBindMethod(this, "DismissContextMenu"), -CONTEXT_MENU_DISMISS_DELAY)
        }

        this.EndSession(modKey)
    }

    DismissContextMenu(*) {
        DispatchSend("{Escape}")
    }

    ; Source-key down (shared entry point)
    OnSourceDown(sourceKey, *) {
        handled := false

        ; Iterate all currently active modifier sessions
        for modKey, session in this.sessions {
            if (session.state = PathCEngine.STATE_IDLE)
                continue

            key := modKey "|" sourceKey
            if !this.mappingByModSource.Has(key)
                continue

            mappings := this.mappingByModSource[key]

            for _, mapping in mappings {
                if !this.IsMappingActive(mapping)
                    continue

                ; Mark this session as a gesture session
                session.state := PathCEngine.STATE_GESTURE_ACTIVE
                session.isGesture := true

                if (mapping.holdRepeat) {
                    this.StartMappingRepeat(mapping, modKey, sourceKey)
                    session.repeatMappings[mapping.id] := true

                    if !session.activeSources.Has(sourceKey)
                        session.activeSources[sourceKey] := []
                    session.activeSources[sourceKey].Push(mapping.id)
                } else {
                    DispatchSend(KeyToSendFormat(mapping.targetKey))
                }

                handled := true
                break
            }

            if (handled)
                break
        }

        if (!handled) {
            ; No Path C mapping matched, fall back to the raw source key
            DispatchSend(KeyToSendFormat(sourceKey))
        }
    }

    ; Source-key up (shared entry point, only for keys that support Up)
    OnSourceUp(sourceKey, *) {
        for modKey, session in this.sessions {
            if (session.state = PathCEngine.STATE_IDLE)
                continue
            if !session.activeSources.Has(sourceKey)
                continue

            ids := session.activeSources[sourceKey]
            for _, mappingId in ids {
                this.StopMappingRepeat(mappingId)
                if (session.repeatMappings.Has(mappingId))
                    session.repeatMappings.Delete(mappingId)
            }
            session.activeSources.Delete(sourceKey)
        }
    }

    ; Whether a Path C wheel source should be routed by this engine
    ; (bound as the HotIf predicate for wheel source hotkeys)
    ShouldRouteWheel(sourceKey, *) {
        if !IsWheelSourceKey(sourceKey)
            return false

        for modKey, session in this.sessions {
            if (session.state = PathCEngine.STATE_IDLE)
                continue

            key := modKey "|" sourceKey
            if !this.mappingByModSource.Has(key)
                continue

            mappings := this.mappingByModSource[key]
            for _, mapping in mappings {
                if this.IsMappingActive(mapping)
                    return true
            }
        }

        return false
    }

    ; Read-only session state snapshot: "Idle" | "HeldNoCombo" | "GestureActive"
    GetSessionState(modKey) {
        if !this.sessions.Has(modKey)
            return PathCEngine.STATE_IDLE
        return this.sessions[modKey].state
    }

    ; ------------------------------------------------------------------------
    ; Internals
    ; ------------------------------------------------------------------------

    ; Get or initialize the session state for a modifier key
    GetSession(modKey) {
        if !this.sessions.Has(modKey)
            this.sessions[modKey] := PathCSession()
        return this.sessions[modKey]
    }

    ; End a modifier session: stop all repeats and reset state
    EndSession(modKey) {
        if !this.sessions.Has(modKey)
            return

        session := this.sessions[modKey]

        ; Stop all repeat timers associated with this modifier
        for mappingId, _ in session.repeatMappings {
            this.StopMappingRepeat(mappingId)
        }

        session.Reset()
    }

    ; Whether a mapping is active in the current foreground window (using checker closure)
    IsMappingActive(mapping) {
        if (mapping.HasOwnProp("checker") && mapping.checker != "") {
            try
                return mapping.checker.Call()
            catch
                return false
        }
        return true
    }

    ; Start Path C long-press repeat for a mapping
    StartMappingRepeat(mapping, modKey, sourceKey) {
        idx := mapping.id
        sendKey := KeyToSendFormat(mapping.targetKey)

        ; Defensive cleanup: stop any existing timer to avoid orphan timers on re-entry
        this.StopMappingRepeat(idx)

        DispatchSend(sendKey)

        timerFn := ObjBindMethod(this, "OnRepeatTick", sendKey, sourceKey, idx, modKey)
        startFn := ObjBindMethod(this, "OnRepeatStart", idx, timerFn, mapping.repeatInterval)
        this.repeatTimers[idx] := { fn: timerFn, startFn: startFn, interval: mapping.repeatInterval, active: true }
        SetTimer(startFn, -mapping.repeatDelay)
    }

    OnRepeatStart(idx, timerFn, interval, *) {
        if (this.repeatTimers.Has(idx) && this.repeatTimers[idx].active)
            SetTimer(timerFn, interval)
    }

    OnRepeatTick(sendKey, sourceKey, idx, modKey, *) {
        ; Ensure the modifier is still held
        if (modKey != "" && !GetKeyState(modKey, "P")) {
            this.StopMappingRepeat(idx)
            return
        }
        ; Safety check: stop repeating if the source key has been released (non-wheel keys)
        baseKey := RegExReplace(sourceKey, "^[+!#^]+", "")
        if (baseKey != "" && !RegExMatch(baseKey, "^Wheel") && !GetKeyState(baseKey, "P")) {
            this.StopMappingRepeat(idx)
            return
        }
        DispatchSend(sendKey)
    }

    StopMappingRepeat(idx) {
        if this.repeatTimers.Has(idx) {
            entry := this.repeatTimers[idx]
            if (entry.HasProp("fn"))
                SetTimer(entry.fn, 0)
            if (entry.HasProp("startFn"))
                SetTimer(entry.startFn, 0)
            entry.active := false
            this.repeatTimers.Delete(idx)
        }
    }
}

; Remove all keys from an engine-owned map in place
ClearEngineMap(mapObj) {
    keys := []
    for key, _ in mapObj
        keys.Push(key)
    for _, key in keys
        mapObj.Delete(key)
}
