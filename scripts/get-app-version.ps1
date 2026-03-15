param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$mainFile = Join-Path $ProjectRoot "src\AHKeyMap.ahk"
if (-not (Test-Path -LiteralPath $mainFile)) {
    throw "Main script not found: $mainFile"
}

$content = Get-Content -LiteralPath $mainFile -Raw -Encoding UTF8

$directiveMatch = [regex]::Match(
    $content,
    '(?m)^;@Ahk2Exe-SetVersion\s+([0-9]+\.[0-9]+\.[0-9]+)\s*$'
)
if (-not $directiveMatch.Success) {
    throw "Failed to find ;@Ahk2Exe-SetVersion in $mainFile"
}

$appVersionMatch = [regex]::Match(
    $content,
    '(?m)^global APP_VERSION := "([0-9]+\.[0-9]+\.[0-9]+)"\s*$'
)
if (-not $appVersionMatch.Success) {
    throw "Failed to find APP_VERSION in $mainFile"
}

$directiveVersion = $directiveMatch.Groups[1].Value
$appVersion = $appVersionMatch.Groups[1].Value

if ($directiveVersion -ne $appVersion) {
    throw "Version mismatch in src/AHKeyMap.ahk: Ahk2Exe=$directiveVersion, APP_VERSION=$appVersion"
}

Write-Output $appVersion
