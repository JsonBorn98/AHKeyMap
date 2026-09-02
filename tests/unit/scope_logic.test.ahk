#Requires AutoHotkey v2.0
#SingleInstance Force

global __AHKM_TEST_MODE := true
global __AHKM_CONFIG_DIR := A_Temp "\AHKeyMapTests\" A_ScriptName "-" A_TickCount "\configs"

#Include "..\..\src\AHKeyMap.ahk"
#Include "..\support\TestBase.ahk"

CurrentLangCode := "en-US"

RegisterTest("CanonicalizeProcessScope normalizes ordering and case", Test_CanonicalizeProcessScope_NormalizesValues)
RegisterTest("ProcessListContains compares process names consistently", Test_ProcessListContains_IsCaseInsensitive)
RegisterTest("IncludeScopesOverlap detects list intersections", Test_IncludeScopesOverlap_DetectsIntersections)
RegisterTest("IncludeVsExcludeOverlap only overlaps on non-excluded targets", Test_IncludeVsExcludeOverlap_UsesIntersectionRules)
RegisterTest("ScopesOverlap covers include, exclude, and global combinations", Test_ScopesOverlap_CoversPriorityCases)
RegisterTest("GetForegroundProcessName consults the foreground hook first", Test_GetForegroundProcessName_ConsultsHookFirst)
RegisterTest("CheckIncludeMatch matches only listed foreground processes", Test_CheckIncludeMatch_UsesForegroundProcessHook)
RegisterTest("CheckExcludeMatch deactivates only for excluded foreground processes", Test_CheckExcludeMatch_UsesForegroundProcessHook)
RegisterTest("MakeProcessChecker gates include and exclude scopes through the foreground query", Test_MakeProcessChecker_ResolvesScopesThroughHook)

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

Test_GetForegroundProcessName_ConsultsHookFirst() {
    SetForegroundProcess("  Scripted.EXE  ")

    ; The scripted name replaces the OS query and is normalized like a real one
    AssertEq("scripted.exe", GetForegroundProcessName())
}

Test_CheckIncludeMatch_UsesForegroundProcessHook() {
    procList := ["Code.exe", "notepad.exe"]

    ; Match: foreground process is in the include list (case-insensitive)
    SetForegroundProcess("code.EXE")
    AssertTrue(CheckIncludeMatch(procList))

    ; No match: foreground process is not in the include list
    SetForegroundProcess("msedge.exe")
    AssertFalse(CheckIncludeMatch(procList))

    ; No match: unknown/empty foreground process never satisfies include scope
    SetForegroundProcess("")
    AssertFalse(CheckIncludeMatch(procList))
}

Test_CheckExcludeMatch_UsesForegroundProcessHook() {
    exclList := ["Code.exe", "notepad.exe"]

    ; Active: foreground process is not excluded
    SetForegroundProcess("msedge.exe")
    AssertTrue(CheckExcludeMatch(exclList))

    ; Inactive: foreground process is in the exclude list (case-insensitive)
    SetForegroundProcess("NOTEPAD.EXE")
    AssertFalse(CheckExcludeMatch(exclList))

    ; Inactive: unknown/empty foreground process fails the guard
    SetForegroundProcess("")
    AssertFalse(CheckExcludeMatch(exclList))
}

Test_MakeProcessChecker_ResolvesScopesThroughHook() {
    includeCfg := BuildConfigRecord("IncludeCfg", "include", "chrome.exe|code.exe")
    includeChecker := MakeProcessChecker(includeCfg)
    AssertTrue(includeChecker != "")

    SetForegroundProcess("Code.EXE")
    AssertTrue(includeChecker.Call())
    SetForegroundProcess("notepad.exe")
    AssertFalse(includeChecker.Call())

    excludeCfg := BuildConfigRecord("ExcludeCfg", "exclude", "", "chrome.exe|code.exe")
    excludeChecker := MakeProcessChecker(excludeCfg)
    AssertTrue(excludeChecker != "")

    SetForegroundProcess("chrome.exe")
    AssertFalse(excludeChecker.Call())
    SetForegroundProcess("notepad.exe")
    AssertTrue(excludeChecker.Call())

    ; Empty lists and global mode produce no checker (effectively global scope)
    AssertEq("", MakeProcessChecker(BuildConfigRecord("EmptyInclude", "include", "")))
    AssertEq("", MakeProcessChecker(BuildConfigRecord("EmptyExclude", "exclude", "", "")))
    AssertEq("", MakeProcessChecker(BuildConfigRecord("GlobalCfg", "global")))
}
