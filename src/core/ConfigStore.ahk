; ============================================================================
; AHKeyMap - Config store module
; Owns AllConfigs, the current selection, and every config/mutation operation.
; Each mutation runs one chokepoint: atomic persist -> hotkey reload -> render.
; ============================================================================

; Globals shared across modules (render functions and engine input stay global)
global AllConfigs
global EnabledCB
global ProcessText

; Deep module for the config working copy:
;   Select(name) / Selected() to read the selected record, and one semantic
;   method per user action. Every mutation runs the same chokepoint:
;   persist (atomic config write + SaveEnabledStates) -> ReloadAllHotkeys()
;   -> render (RefreshConfigList / RefreshMappingLV / UpdateStatusText).
; Production code uses the lazy singleton `ConfigStore.Instance`; tests may
; reset the singleton via ResetConfigStoreForTests().
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

    ; Select a config by name ("" clears the selection) and render it
    Select(name) {
        this.selName := name
        cfg := this.Selected()
        if (cfg = "")
            this.selName := ""
        if (cfg != "") {
            this.RenderScopeControls(FormatProcessDisplay(cfg["processMode"], cfg["processList"], cfg["excludeProcessList"]), cfg["enabled"], true)
            RefreshMappingLV()
            ; Persist last viewed config name into _state.ini
            try IniWrite(name, STATE_FILE, "State", "LastConfig")
        } else {
            this.RenderScopeControls(L("Config.Scope.None"), 0, false)
            RefreshMappingLV()
        }
    }

    ; Render the scope text and enable checkbox (no-op without a GUI)
    RenderScopeControls(scopeText, enabledFlag, enabledEditable) {
        if (IsObject(ProcessText))
            ProcessText.Value := scopeText
        if (IsObject(EnabledCB)) {
            EnabledCB.Value := enabledFlag
            EnabledCB.Enabled := enabledEditable
        }
    }

    ; Enable/disable the selected config
    SetEnabled(flag) {
        cfg := this.Selected()
        if (cfg = "")
            return
        cfg["enabled"] := (flag ? true : false)
        if (IsObject(EnabledCB))
            EnabledCB.Value := cfg["enabled"]
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

        if (IsObject(ProcessText))
            ProcessText.Value := FormatProcessDisplay(mode, cfg["processList"], cfg["excludeProcessList"])
        this.RunChokepoint()
    }

    ; Append a mapping to the selected config; returns the new index (0 on failure)
    AddMapping(mapping) {
        cfg := this.Selected()
        if (cfg = "")
            return 0
        cfg["mappings"].Push(mapping)
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
        cfg["mappings"][index] := mapping
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

        IniWrite(name, newFile, "Meta", "Name")
        IniWrite(mode, newFile, "Meta", "ProcessMode")
        if (mode = "include") {
            IniWrite(procStr, newFile, "Meta", "Process")
            IniWrite("", newFile, "Meta", "ExcludeProcess")
        } else if (mode = "exclude") {
            IniWrite("", newFile, "Meta", "Process")
            IniWrite(procStr, newFile, "Meta", "ExcludeProcess")
        } else {
            IniWrite("", newFile, "Meta", "Process")
            IniWrite("", newFile, "Meta", "ExcludeProcess")
        }

        ; Enable new config by default
        IniWrite("1", STATE_FILE, "EnabledConfigs", name)

        LoadAllConfigs()
        RefreshConfigList(name)
        ReloadAllHotkeys()
    }

    ; Copy the selected config under a new name and select the copy
    CopyConfig(newName) {
        cfg := this.Selected()
        if (cfg = "")
            return
        newFile := CONFIG_DIR "\" newName ".ini"
        if FileExist(newFile)
            return

        if FileExist(cfg["file"])
            FileCopy(cfg["file"], newFile)

        ; Update Name field inside copied config
        IniWrite(newName, newFile, "Meta", "Name")

        ; Enable new config by default
        IniWrite("1", STATE_FILE, "EnabledConfigs", newName)

        LoadAllConfigs()
        RefreshConfigList(newName)
        ReloadAllHotkeys()
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
        ReloadAllHotkeys()
        RefreshConfigList()
    }

    ; ------------------------------------------------------------------------
    ; Chokepoint
    ; ------------------------------------------------------------------------

    ; Single mutation flow: persist the selected config (atomic write plus
    ; enabled states) -> reload all hotkeys -> render the mapping list.
    ; Every mutation, including SetEnabled, runs this exact sequence.
    RunChokepoint() {
        cfg := this.Selected()
        if (cfg != "")
            SaveConfig(cfg)
        SaveEnabledStates()
        ReloadAllHotkeys()
        RefreshMappingLV()
    }

    ; ------------------------------------------------------------------------
    ; Reset
    ; ------------------------------------------------------------------------

    ; Clear the selection without touching the GUI or AllConfigs
    ; (test/teardown helper, mirrors PathCEngine.Reset())
    Reset() {
        this.selName := ""
    }
}

; Test seam: reset the singleton so the next Instance access builds a fresh
; store with an empty selection (mirrors ResetAppState clearing AllConfigs)
ResetConfigStoreForTests() {
    ConfigStore._instance := ""
}
