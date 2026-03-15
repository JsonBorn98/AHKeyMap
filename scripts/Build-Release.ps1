param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDir = "",
    [string]$Ahk2ExePath = "",
    [string]$BaseFilePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory)]
        [string]$PathValue,
        [Parameter(Mandatory)]
        [string]$Label
    )

    $resolved = Resolve-Path -LiteralPath $PathValue -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw "$Label not found: $PathValue"
    }
    return $resolved.Path
}

function Find-LocalToolchain {
    $candidates = @()

    if ($env:ProgramFiles) {
        $candidates += @{
            Ahk2Exe = Join-Path $env:ProgramFiles "AutoHotkey\Compiler\Ahk2Exe.exe"
            BaseFile = Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey64.exe"
        }
    }

    if (${env:ProgramFiles(x86)}) {
        $candidates += @{
            Ahk2Exe = Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\Compiler\Ahk2Exe.exe"
            BaseFile = Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\v2\AutoHotkey64.exe"
        }
    }

    if ($env:LocalAppData) {
        $candidates += @{
            Ahk2Exe = Join-Path $env:LocalAppData "Programs\AutoHotkey\Compiler\Ahk2Exe.exe"
            BaseFile = Join-Path $env:LocalAppData "Programs\AutoHotkey\v2\AutoHotkey64.exe"
        }
    }

    $scoopRoot = Join-Path $env:UserProfile "scoop\apps\autohotkey"
    if (Test-Path -LiteralPath $scoopRoot) {
        Get-ChildItem -LiteralPath $scoopRoot -Directory | ForEach-Object {
            $candidates += @{
                Ahk2Exe = Join-Path $_.FullName "Compiler\Ahk2Exe.exe"
                BaseFile = Join-Path $_.FullName "v2\AutoHotkey64.exe"
            }
        }
    }

    foreach ($candidate in $candidates) {
        if ((Test-Path -LiteralPath $candidate.Ahk2Exe) -and (Test-Path -LiteralPath $candidate.BaseFile)) {
            return $candidate
        }
    }

    $ahk2ExeCommand = Get-Command "Ahk2Exe.exe" -ErrorAction SilentlyContinue
    if ($ahk2ExeCommand) {
        foreach ($candidate in $candidates) {
            if (Test-Path -LiteralPath $candidate.BaseFile) {
                return @{
                    Ahk2Exe = $ahk2ExeCommand.Source
                    BaseFile = $candidate.BaseFile
                }
            }
        }
    }

    throw "AutoHotkey toolchain not found. Provide -Ahk2ExePath and -BaseFilePath, or install AutoHotkey v2 locally."
}

function Resolve-Toolchain {
    param(
        [string]$CompilerPath,
        [string]$InterpreterPath
    )

    if ($CompilerPath -and $InterpreterPath) {
        return @{
            Ahk2Exe = Resolve-ExistingPath -PathValue $CompilerPath -Label "Ahk2Exe"
            BaseFile = Resolve-ExistingPath -PathValue $InterpreterPath -Label "AutoHotkey base file"
        }
    }

    if ($CompilerPath -or $InterpreterPath) {
        throw "Provide both -Ahk2ExePath and -BaseFilePath, or neither."
    }

    return Find-LocalToolchain
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $ProjectRoot "dist"
}

$getVersionScript = Join-Path $PSScriptRoot "Get-AppVersion.ps1"
$version = (& $getVersionScript -ProjectRoot $ProjectRoot).Trim()
$toolchain = Resolve-Toolchain -CompilerPath $Ahk2ExePath -InterpreterPath $BaseFilePath

$mainScript = Join-Path $ProjectRoot "AHKeyMap.ahk"
$iconFile = Join-Path $ProjectRoot "icon.ico"
$readmeFile = Join-Path $ProjectRoot "README.md"
$licenseFile = Join-Path $ProjectRoot "LICENSE"
$noticeFile = Join-Path $ProjectRoot "THIRD_PARTY_NOTICES.md"

foreach ($requiredFile in @($mainScript, $iconFile, $readmeFile, $licenseFile)) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required file not found: $requiredFile"
    }
}

$distDir = [System.IO.Path]::GetFullPath($OutputDir)
if (Test-Path -LiteralPath $distDir) {
    Remove-Item -LiteralPath $distDir -Recurse -Force
}
New-Item -ItemType Directory -Path $distDir | Out-Null

$exePath = Join-Path $distDir "AHKeyMap.exe"
$zipName = "AHKeyMap-v$version-windows-x64.zip"
$zipPath = Join-Path $distDir $zipName
$hashPath = Join-Path $distDir "SHA256SUMS.txt"
$stageDir = Join-Path $distDir "package"

Write-Host "Using Ahk2Exe: $($toolchain.Ahk2Exe)"
Write-Host "Using base file: $($toolchain.BaseFile)"
Write-Host "Building version: $version"

$compileProcess = Start-Process `
    -FilePath $toolchain.Ahk2Exe `
    -ArgumentList @(
        "/in", $mainScript,
        "/out", $exePath,
        "/icon", $iconFile,
        "/base", $toolchain.BaseFile
    ) `
    -Wait `
    -PassThru

if ($compileProcess.ExitCode -ne 0) {
    throw "Ahk2Exe failed with exit code $($compileProcess.ExitCode)"
}

if (-not (Test-Path -LiteralPath $exePath)) {
    throw "Build output not found: $exePath"
}

New-Item -ItemType Directory -Path $stageDir | Out-Null
Copy-Item -LiteralPath $exePath -Destination (Join-Path $stageDir "AHKeyMap.exe")
Copy-Item -LiteralPath $readmeFile -Destination (Join-Path $stageDir "README.md")
Copy-Item -LiteralPath $licenseFile -Destination (Join-Path $stageDir "LICENSE")
if (Test-Path -LiteralPath $noticeFile) {
    Copy-Item -LiteralPath $noticeFile -Destination (Join-Path $stageDir "THIRD_PARTY_NOTICES.md")
}

Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -Force
Remove-Item -LiteralPath $stageDir -Recurse -Force

$hashLines = foreach ($artifactPath in @($exePath, $zipPath)) {
    $hash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "{0}  {1}" -f $hash, (Split-Path -Leaf $artifactPath)
}
Set-Content -LiteralPath $hashPath -Value $hashLines -Encoding Ascii

Write-Host "Artifacts created:"
Write-Host "  $exePath"
Write-Host "  $zipPath"
Write-Host "  $hashPath"
