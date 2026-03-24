#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

RegisterTest("L() returns correct English string for known key", Test_L_ReturnsEnglishString)
RegisterTest("L() returns correct Chinese string for known key", Test_L_ReturnsChineseString)
RegisterTest("L() formats positional arguments in template", Test_L_FormatsArguments)
RegisterTest("L() falls back to English for unknown language code", Test_L_FallsBackToEnglish)
RegisterTest("L() returns bracketed key name for missing key", Test_L_ReturnsBracketedKeyForMissing)
RegisterTest("English and Chinese packs have identical key sets", Test_EnAndZhPacksHaveIdenticalKeys)
RegisterTest("DetectDefaultLanguage returns en-US", Test_DetectDefaultLanguage_ReturnsEnUS)

RunRegisteredTests()

; ============================================================================
; Test implementations
; ============================================================================

Test_L_ReturnsEnglishString() {
    global CurrentLangCode := "en-US"
    AssertEq("Config:", L("GuiMain.ConfigLabel"))
    AssertEq("On", L("GuiMain.EnableCheckbox"))
    AssertEq("New", L("GuiMain.NewConfigButton"))
}

Test_L_ReturnsChineseString() {
    global CurrentLangCode := "zh-CN"
    AssertEq("配置:", L("GuiMain.ConfigLabel"))
}

Test_L_FormatsArguments() {
    global CurrentLangCode := "en-US"
    ; GuiMain.Title template is "{1} v{2}"
    result := L("GuiMain.Title", "AHKeyMap", "2.9.2")
    AssertEq("AHKeyMap v2.9.2", result)
}

Test_L_FallsBackToEnglish() {
    global CurrentLangCode := "de-DE"
    ; Unknown lang code should fall back to en-US pack
    AssertEq("Config:", L("GuiMain.ConfigLabel"))
}

Test_L_ReturnsBracketedKeyForMissing() {
    global CurrentLangCode := "en-US"
    AssertEq("[Nonexistent.Key]", L("Nonexistent.Key"))

    ; Also verify with zh-CN — missing key falls back to en-US then brackets
    global CurrentLangCode := "zh-CN"
    AssertEq("[Also.Missing.Key]", L("Also.Missing.Key"))
}

Test_EnAndZhPacksHaveIdenticalKeys() {
    enPack := BuildEnPack()
    zhPack := BuildZhPack()

    ; Check every English key exists in Chinese pack
    missingInZh := []
    for key, _ in enPack {
        if !zhPack.Has(key)
            missingInZh.Push(key)
    }

    ; Check every Chinese key exists in English pack
    missingInEn := []
    for key, _ in zhPack {
        if !enPack.Has(key)
            missingInEn.Push(key)
    }

    if (missingInZh.Length > 0) {
        details := ""
        for _, key in missingInZh
            details .= key "`n"
        Fail("Keys in en-US but missing from zh-CN:`n" details)
    }

    if (missingInEn.Length > 0) {
        details := ""
        for _, key in missingInEn
            details .= key "`n"
        Fail("Keys in zh-CN but missing from en-US:`n" details)
    }

    ; Sanity check: both packs should have a non-trivial number of keys
    AssertTrue(enPack.Count > 20, "English pack should have > 20 keys, got " enPack.Count)
    AssertTrue(zhPack.Count > 20, "Chinese pack should have > 20 keys, got " zhPack.Count)
}

Test_DetectDefaultLanguage_ReturnsEnUS() {
    AssertEq("en-US", DetectDefaultLanguage())
}
