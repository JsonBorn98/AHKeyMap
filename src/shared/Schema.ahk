; ============================================================================
; AHKeyMap - Record schema module
; Static-only namespaces owning what a mapping/config record is: construction,
; normalization (whitelist + coercion + defaults + clamp), path classification,
; hotkey-string derivation, and the INI serialization field list.
; Records stay plain Map()s; the schema lives in these constructors, not in a
; new storage type.
; ============================================================================

; Globals shared across modules (referenced at call time, never re-initialized)
global DEFAULT_REPEAT_DELAY
global DEFAULT_REPEAT_INTERVAL
global CONFIG_DIR

; ============================================================================
; Mapping schema
; ============================================================================

; Static namespace for one mapping record:
;   ModifierKey / SourceKey / TargetKey  - AHK key names ("" = none)
;   HoldRepeat / PassthroughMod          - 0/1 flags
;   RepeatDelay / RepeatInterval         - long-press timing in ms (>= 10)
class Mapping {
    ; Path constants: A = plain hotkey, B = intercept combo, C = passthrough combo
    static PATH_A := "A"
    static PATH_B := "B"
    static PATH_C := "C"

    ; Minimum supported long-press timing (ms); smaller values are clamped
    static MIN_REPEAT_TIMING := 10

    ; Construct one normalized mapping record (the single construction entry)
    static Make(modKey, sourceKey, targetKey, holdRepeat := 0, repeatDelay := "", repeatInterval := "", passthroughMod := 0) {
        m := Map()
        m["ModifierKey"] := modKey
        m["SourceKey"] := sourceKey
        m["TargetKey"] := targetKey
        m["HoldRepeat"] := holdRepeat
        m["RepeatDelay"] := repeatDelay
        m["RepeatInterval"] := repeatInterval
        m["PassthroughMod"] := passthroughMod
        Mapping.Normalize(m)
        return m
    }

    ; Enforce the record invariants in place:
    ;   - whitelist: keep only the seven schema fields (extras are dropped)
    ;   - Integer() coercion of the numeric fields (fallback to defaults)
    ;   - defaults from DEFAULT_REPEAT_DELAY / DEFAULT_REPEAT_INTERVAL
    ;   - RepeatDelay / RepeatInterval clamped to >= MIN_REPEAT_TIMING
    static Normalize(m) {
        defaults := Map(
            "ModifierKey", "",
            "SourceKey", "",
            "TargetKey", "",
            "HoldRepeat", 0,
            "RepeatDelay", DEFAULT_REPEAT_DELAY,
            "RepeatInterval", DEFAULT_REPEAT_INTERVAL,
            "PassthroughMod", 0
        )

        ; Whitelist: drop any key outside the seven-field schema
        extraKeys := []
        for keyName, _ in m {
            if !defaults.Has(keyName)
                extraKeys.Push(keyName)
        }
        for _, keyName in extraKeys
            m.Delete(keyName)

        ; Fill defaults for missing fields
        for keyName, defaultValue in defaults {
            if !m.Has(keyName)
                m[keyName] := defaultValue
        }

        ; Integer coercion for the numeric fields (unparseable values fall back)
        m["HoldRepeat"] := Mapping.ToIntOr(m["HoldRepeat"], 0)
        m["RepeatDelay"] := Mapping.ToIntOr(m["RepeatDelay"], DEFAULT_REPEAT_DELAY)
        m["RepeatInterval"] := Mapping.ToIntOr(m["RepeatInterval"], DEFAULT_REPEAT_INTERVAL)
        m["PassthroughMod"] := Mapping.ToIntOr(m["PassthroughMod"], 0)

        ; Clamp repeat timing to the minimum supported value
        if (m["RepeatDelay"] < Mapping.MIN_REPEAT_TIMING)
            m["RepeatDelay"] := Mapping.MIN_REPEAT_TIMING
        if (m["RepeatInterval"] < Mapping.MIN_REPEAT_TIMING)
            m["RepeatInterval"] := Mapping.MIN_REPEAT_TIMING
    }

    ; The single path rule: A (no modifier), B (intercept combo), C (passthrough combo)
    static ClassifyPath(m) {
        if (m["ModifierKey"] = "")
            return Mapping.PATH_A
        if (!m["PassthroughMod"])
            return Mapping.PATH_B
        return Mapping.PATH_C
    }

    ; The single hotkey-string derivation, used by registration and conflict
    ; detection so the two can never drift apart
    static HotkeyStringFor(m) {
        path := Mapping.ClassifyPath(m)
        if (path = Mapping.PATH_A)
            return m["SourceKey"]
        if (path = Mapping.PATH_B)
            return m["ModifierKey"] " & " m["SourceKey"]
        return "~" m["ModifierKey"] "+" m["SourceKey"]
    }

    ; The single serialization field list (INI key -> string value, in write order)
    static ToIniPairs(m) {
        pairs := Map()
        pairs["ModifierKey"] := String(m["ModifierKey"])
        pairs["SourceKey"] := String(m["SourceKey"])
        pairs["TargetKey"] := String(m["TargetKey"])
        pairs["HoldRepeat"] := String(m["HoldRepeat"])
        pairs["RepeatDelay"] := String(m["RepeatDelay"])
        pairs["RepeatInterval"] := String(m["RepeatInterval"])
        pairs["PassthroughMod"] := String(m["PassthroughMod"])
        return pairs
    }

    ; Coerce a value to Integer, falling back when empty or unparseable
    static ToIntOr(value, fallback) {
        if (value = "")
            return fallback
        try
            return Integer(value)
        catch
            return fallback
    }
}

; ============================================================================
; Config record schema
; ============================================================================

; Static namespace for one config record: owns the record shape, the
; ParseProcessList derivation, and the config file path.
class ConfigRecord {
    static Make(name, processMode, process, excludeProcess, enabled, mappings) {
        cfg := Map()
        cfg["name"] := name
        cfg["file"] := CONFIG_DIR "\" name ".ini"
        cfg["processMode"] := processMode
        cfg["process"] := process
        cfg["processList"] := ParseProcessList(process)
        cfg["excludeProcess"] := excludeProcess
        cfg["excludeProcessList"] := ParseProcessList(excludeProcess)
        cfg["enabled"] := enabled
        cfg["mappings"] := mappings
        return cfg
    }
}
