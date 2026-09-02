; ============================================================================
; AHKeyMap - Config store module
; Owns AllConfigs, the current selection, and every config/mutation operation.
; Each mutation runs one chokepoint: atomic persist -> hotkey reload -> notify.
; ============================================================================

; Globals shared across modules (engine input stays global)
global AllConfigs

; Deep module for the config working copy:
;   Select(name) / Selected() to read the selected record, and one semantic
;   method per user action. Every mutation runs the same chokepoint:
;   persist (atomic config write + SaveEnabledStates) -> ReloadAllHotkeys()
;   -> OnChanged(reloadResult).
; The store never touches the GUI: rendering happens in whatever the host
; registered into the OnChanged slot (the ui layer registers its render
; entry; headless tests register nothing). Production code uses the lazy
; singleton `ConfigStore.Instance`; tests may reset the singleton via
; ResetConfigStoreForTests().
class ConfigStore {
    static _instance := ""

    static Instance {
        get {
            if (ConfigStore._instance = "")
                ConfigStore._instance := ConfigStore()
            return ConfigStore._instance
        }
    }

    __New() {
        ; Name of the selected config ("" when nothing is selected).
        ; Field name must differ from the SelectedName property (AHK v2
        ; identifiers are case-insensitive; same name would be read-only).
        this.selName := ""
        ; Callback slot fired after every chokepoint with the ReloadAllHotkeys
        ; result; the host (GUI) owns rendering, core stays ui-free.
        this.onChanged := ""
    }

    ; ------------------------------------------------------------------------
    ; OnChanged seam
    ; ------------------------------------------------------------------------

    ; Register the change-notification callback: OnChanged(reloadResult)
    ; reloadResult is the Map returned by ReloadAllHotkeys() ({conflicts,
    ; regErrors}). Register "" to clear. One subscriber is all this seam
    ; needs; it exists to invert the core->ui dependency direction.
    SetOnChanged(callback) {
        this.onChanged := callback
    }

    ; Fire the registered callback (no-op when nothing is registered)
    NotifyChanged(reloadResult) {
        if (this.onChanged = "")
            return
        this.onChanged.Call(reloadResult)
    }

    ; ------------------------------------------------------------------------
    ; State access
    ; ------------------------------------------------------------------------

    ; Name of the currently selected config ("" = no selection)
    SelectedName {
        get {
            return this.selName
        }
    }

    ; The selected config record, or "" when nothing is selected
    Selected() {
        if (this.selName = "")
            return ""
        idx := this.FindIndex(this.selName)
        if (idx = 0)
            return ""
        return AllConfigs[idx]
    }

    ; The mappings array of the selected config (or an empty standalone array)
    SelectedMappings() {
        cfg := this.Selected()
        if (cfg = "")
            return []
        return cfg["mappings"]
    }

    ; Find config index by name in AllConfigs (0 = not found)
    FindIndex(configName) {
        for i, cfg in AllConfigs {
            if (cfg["name"] = configName)
                return i
        }
        return 0
    }

    ; ------------------------------------------------------------------------
    ; Semantic mutations (each runs the single chokepoint internally)
    ; ------------------------------------------------------------------------

    ; Select a config by name ("" clears the selection), persist the last
    ; viewed name, and notify. Selection itself is render-only (no hotkey
    ; reload), so it notifies with the unchanged "" result.
    Select(name) {
        this.selName := name
        cfg := this.Selected()
        if (cfg = "")
            this.selName := ""
        if (cfg != "") {
            ; Persist last viewed config name into _state.ini
            try IniWrite(name, STATE_FILE, "State", "LastConfig")
        }
        this.NotifyChanged("")
    }

    ; Enable/disable the selected config
    SetEnabled(flag) {
        cfg := this.Selected()
        if (cfg = "")
            return
        cfg["enabled"] := (flag ? true : false)
        this.RunChokepoint()
    }

    ; Change process scope of the selected config; keeps include/exclude/global
    ; branch consistency (only the active branch keeps its process list)
    SetScope(mode, procStr) {
        cfg := this.Selected()
        if (cfg = "")
            return

        cfg["processMode"] := mode
        if (mode = "include") {
            cfg["process"] := procStr
            cfg["processList"] := ParseProcessList(procStr)
            cfg["excludeProcess"] := ""
            cfg["excludeProcessList"] := []
        } else if (mode = "exclude") {
            cfg["process"] := ""
            cfg["processList"] := []
            cfg["excludeProcess"] := procStr
            cfg["excludeProcessList"] := ParseProcessList(procStr)
        } else {
            cfg["process"] := ""
            cfg["processList"] := []
            cfg["excludeProcess"] := ""
            cfg["excludeProcessList"] := []
        }

        this.RunChokepoint()
    }

    ; Append a mapping to the selected config; returns the new index (0 on failure)
    AddMapping(mapping) {
        cfg := this.Selected()
        if (cfg = "")
            return 0
        cfg["mappings"].Push(this.NormalizeIncomingMapping(mapping))
        this.RunChokepoint()
        return cfg["mappings"].Length
    }

    ; Replace the mapping at the given index (1-based) in the selected config
    ReplaceMapping(index, mapping) {
        cfg := this.Selected()
        if (cfg = "")
            return
        if (index < 1 || index > cfg["mappings"].Length)
            return
        cfg["mappings"][index] := this.NormalizeIncomingMapping(mapping)
        this.RunChokepoint()
    }

    ; Delete the mapping at the given index (1-based) from the selected config
    DeleteMapping(index) {
        cfg := this.Selected()
        if (cfg = "")
            return
        if (index < 1 || index > cfg["mappings"].Length)
            return
        cfg["mappings"].RemoveAt(index)
        this.RunChokepoint()
    }

    ; Create a new config with the given scope and select it
    CreateConfig(name, mode, procStr) {
        newFile := CONFIG_DIR "\" name ".ini"
        if FileExist(newFile)
            return
        tempFile := newFile ".tmp"

        try {
            if FileExist(tempFile)
                FileDelete(tempFile)

            ; Stage the new config in a temp file (atomic write pattern:
            ; the config path only ever sees a complete file)
            IniWrite(name, tempFile, "Meta", "Name")
            IniWrite(mode, tempFile, "Meta", "ProcessMode")
            if (mode = "include") {
                IniWrite(procStr, tempFile, "Meta", "Process")
                IniWrite("", tempFile, "Meta", "ExcludeProcess")
            } else if (mode = "exclude") {
                IniWrite("", tempFile, "Meta", "Process")
                IniWrite(procStr, tempFile, "Meta", "ExcludeProcess")
            } else {
                IniWrite("", tempFile, "Meta", "Process")
                IniWrite("", tempFile, "Meta", "ExcludeProcess")
            }
            FileMove(tempFile, newFile, 1)

            ; Enable new config by default
            IniWrite("1", STATE_FILE, "EnabledConfigs", name)
        } catch as e {
            ; Remove staged/partial files so the name can be retried
            try FileDelete(tempFile)
            try FileDelete(newFile)
            MsgBox(Format(L("Config.CreateError"), e.Message, newFile), APP_NAME, "IconX")
            return
        }

        LoadAllConfigs()
        this.NotifyChokepointReload()
        this.Select(name)
    }

    ; Copy the selected config under a new name and select the copy
    CopyConfig(newName) {
        cfg := this.Selected()
        if (cfg = "")
            return
        newFile := CONFIG_DIR "\" newName ".ini"
        if FileExist(newFile)
            return
        tempFile := newFile ".tmp"

        try {
            if FileExist(tempFile)
                FileDelete(tempFile)

            ; Stage the copy in a temp file (atomic write pattern)
            if FileExist(cfg["file"])
                FileCopy(cfg["file"], tempFile)

            ; Update Name field inside copied config
            IniWrite(newName, tempFile, "Meta", "Name")
            FileMove(tempFile, newFile, 1)

            ; Enable new config by default
            IniWrite("1", STATE_FILE, "EnabledConfigs", newName)
        } catch as e {
            ; Remove staged/partial files so the name can be retried
            try FileDelete(tempFile)
            try FileDelete(newFile)
            MsgBox(Format(L("Config.CopyError"), e.Message, newFile), APP_NAME, "IconX")
            return
        }

        LoadAllConfigs()
        this.NotifyChokepointReload()
        this.Select(newName)
    }

    ; Delete the selected config (file + record) and clear the selection
    DeleteConfig() {
        cfg := this.Selected()
        if (cfg = "")
            return

        if FileExist(cfg["file"])
            FileDelete(cfg["file"])

        idx := this.FindIndex(cfg["name"])
        if (idx > 0)
            AllConfigs.RemoveAt(idx)

        this.selName := ""

        SaveEnabledStates()
        this.NotifyChokepointReload()

        ; Keep the selection valid after a delete: adopt the first remaining
        ; config (nothing when the list is now empty). This is a store-side
        ; decision — render functions never mutate the store, so the old
        ; "dropdown adopts item 1 during render" behavior lives here instead.
        if (AllConfigs.Length > 0)
            this.Select(AllConfigs[1]["name"])
    }

    ; ------------------------------------------------------------------------
    ; Internals
    ; ------------------------------------------------------------------------

    ; Boundary guarantee: every mapping entering the working copy is
    ; re-normalized so all stored records satisfy the schema invariants
    ; (local name avoids shadowing the Mapping class; AHK names are
    ; case-insensitive)
    NormalizeIncomingMapping(m) {
        if (Type(m) != "Map")
            return Mapping.Make("", "", "")
        Mapping.Normalize(m)
        return m
    }

    ; ------------------------------------------------------------------------
    ; Chokepoint
    ; ------------------------------------------------------------------------

    ; Single mutation flow: persist the selected config (atomic write plus
    ; enabled states) -> reload all hotkeys -> notify with the reload result.
    ; Every mutation, including SetEnabled, runs this exact sequence.
    RunChokepoint() {
        cfg := this.Selected()
        if (cfg != "")
            SaveConfig(cfg)
        SaveEnabledStates()
        this.NotifyChokepointReload()
    }

    ; Reload hotkeys and hand the result to the OnChanged subscriber
    NotifyChokepointReload() {
        this.NotifyChanged(ReloadAllHotkeys())
    }

    ; ------------------------------------------------------------------------
    ; Reset
    ; ------------------------------------------------------------------------

    ; Clear the selection and the OnChanged registration without touching
    ; AllConfigs (test/teardown helper, mirrors PathCEngine.Reset())
    Reset() {
        this.selName := ""
        this.onChanged := ""
    }
}

; Test seam: reset the singleton so the next Instance access builds a fresh
; store with an empty selection (mirrors ResetAppState clearing AllConfigs)
ResetConfigStoreForTests() {
    ConfigStore._instance := ""
}
