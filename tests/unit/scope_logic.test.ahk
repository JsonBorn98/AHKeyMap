#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\AHKeyMap.ahk"
#Include "..\_support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("CanonicalizeProcessScope normalizes ordering and case", Test_CanonicalizeProcessScope_NormalizesValues)
RegisterTest("ProcessListContains compares process names consistently", Test_ProcessListContains_IsCaseInsensitive)
RegisterTest("IncludeScopesOverlap detects list intersections", Test_IncludeScopesOverlap_DetectsIntersections)
RegisterTest("IncludeVsExcludeOverlap only overlaps on non-excluded targets", Test_IncludeVsExcludeOverlap_UsesIntersectionRules)
RegisterTest("ScopesOverlap covers include, exclude, and global combinations", Test_ScopesOverlap_CoversPriorityCases)

RunRegisteredTests()

Test_CanonicalizeProcessScope_NormalizesValues() {
    normalized := CanonicalizeProcessScope(" Code.exe |notepad.exe|code.exe|  chrome.exe ")
    AssertEq("chrome.exe|code.exe|notepad.exe", normalized)
}

Test_ProcessListContains_IsCaseInsensitive() {
    AssertTrue(ProcessListContains(["Code.exe", "notepad.exe"], "code.exe"))
    AssertTrue(ProcessListContains(["Code.exe", "notepad.exe"], "  NOTEPAD.EXE "))
    AssertFalse(ProcessListContains(["Code.exe", "notepad.exe"], "msedge.exe"))
}

Test_IncludeScopesOverlap_DetectsIntersections() {
    AssertTrue(IncludeScopesOverlap("chrome.exe|code.exe", "code.exe|notepad.exe"))
    AssertFalse(IncludeScopesOverlap("chrome.exe", "notepad.exe"))
}

Test_IncludeVsExcludeOverlap_UsesIntersectionRules() {
    AssertTrue(IncludeVsExcludeOverlap("chrome.exe|code.exe", "chrome.exe"))
    AssertFalse(IncludeVsExcludeOverlap("chrome.exe", "chrome.exe"))
    AssertTrue(IncludeVsExcludeOverlap("code.exe", ""))
}

Test_ScopesOverlap_CoversPriorityCases() {
    AssertTrue(ScopesOverlap("global", "", "exclude", "chrome.exe"))
    AssertTrue(ScopesOverlap("include", "code.exe", "global", ""))
    AssertTrue(ScopesOverlap("include", "code.exe|chrome.exe", "exclude", "chrome.exe"))
    AssertFalse(ScopesOverlap("include", "code.exe", "exclude", "code.exe"))
    AssertFalse(ScopesOverlap("include", "code.exe", "include", "notepad.exe"))
    AssertTrue(ScopesOverlap("exclude", "chrome.exe", "exclude", "code.exe"))
}
