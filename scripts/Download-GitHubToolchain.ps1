param(
    [string]$AutoHotkeyVersion,
    [string]$Ahk2ExeVersion,
    [string]$OutputRoot = (Join-Path $env:RUNNER_TEMP "ahk-toolchain")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Download-FromCandidates {
    param(
        [Parameter(Mandatory)]
        [string[]]$Urls,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    foreach ($url in $Urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $DestinationPath
            return $url
        } catch {
            Write-Host "Download failed, trying next URL: $url"
        }
    }

    throw "Unable to download artifact. Tried:`n$($Urls -join "`n")"
}

if (Test-Path -LiteralPath $OutputRoot) {
    Remove-Item -LiteralPath $OutputRoot -Recurse -Force
}

$autoHotkeyRoot = Join-Path $OutputRoot "autohotkey"
$ahk2ExeRoot = Join-Path $OutputRoot "ahk2exe"
$compilerDir = Join-Path $autoHotkeyRoot "Compiler"

New-Item -ItemType Directory -Path $autoHotkeyRoot | Out-Null
New-Item -ItemType Directory -Path $ahk2ExeRoot | Out-Null
New-Item -ItemType Directory -Path $compilerDir | Out-Null

$autoHotkeyZip = Join-Path $OutputRoot "AutoHotkey.zip"
$autoHotkeyUrl = "https://github.com/AutoHotkey/AutoHotkey/releases/download/v$AutoHotkeyVersion/AutoHotkey_$AutoHotkeyVersion.zip"
Write-Host "Downloading AutoHotkey runtime from $autoHotkeyUrl"
Invoke-WebRequest -Uri $autoHotkeyUrl -OutFile $autoHotkeyZip
Expand-Archive -LiteralPath $autoHotkeyZip -DestinationPath $autoHotkeyRoot -Force

$ahk2ExeExe = Join-Path $compilerDir "Ahk2Exe.exe"
$downloadedFrom = Download-FromCandidates -Urls @(
    "https://github.com/AutoHotkey/Ahk2Exe/releases/download/Ahk2Exe$Ahk2ExeVersion/Ahk2Exe.exe",
    "https://github.com/AutoHotkey/Ahk2Exe/releases/download/v$Ahk2ExeVersion/Ahk2Exe.exe"
) -DestinationPath $ahk2ExeExe
Write-Host "Downloading Ahk2Exe from $downloadedFrom"

$baseFile = Get-ChildItem -Path $autoHotkeyRoot -Recurse -Filter AutoHotkey64.exe | Select-Object -First 1
if (-not $baseFile) {
    throw "AutoHotkey64.exe not found after extracting AutoHotkey runtime"
}

if (-not (Test-Path -LiteralPath $ahk2ExeExe)) {
    throw "Ahk2Exe.exe not found after download"
}

"AHK2EXE_PATH=$ahk2ExeExe" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"AHK_BASE_FILE=$($baseFile.FullName)" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
