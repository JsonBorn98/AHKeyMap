param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot),
    [string[]]$Suite = @("all"),
    [switch]$Ci,
    [string]$AutoHotkeyPath = "",
    [string]$OutputDir = ""
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

function Resolve-SuiteSelection {
    param(
        [Parameter(Mandatory)]
        [string[]]$SuiteValues
    )

    $allowed = @("unit", "integration", "gui", "all")
    $expanded = New-Object System.Collections.Generic.List[string]

    foreach ($rawValue in $SuiteValues) {
        foreach ($item in ($rawValue -split ",")) {
            $value = $item.Trim().ToLowerInvariant()
            if (-not $value) {
                continue
            }

            if ($allowed -notcontains $value) {
                throw "Unsupported suite '$value'. Use unit, integration, gui, or all."
            }

            if ($value -eq "all") {
                return @("unit", "integration", "gui")
            }

            if (-not $expanded.Contains($value)) {
                $expanded.Add($value)
            }
        }
    }

    if ($expanded.Count -eq 0) {
        return @("unit", "integration", "gui")
    }

    return $expanded.ToArray()
}

function Resolve-AutoHotkeyRuntime {
    param(
        [string]$RequestedPath
    )

    if ($RequestedPath) {
        return Resolve-ExistingPath -PathValue $RequestedPath -Label "AutoHotkey runtime"
    }

    if ($env:AHK_BASE_FILE -and (Test-Path -LiteralPath $env:AHK_BASE_FILE)) {
        return (Resolve-Path -LiteralPath $env:AHK_BASE_FILE).Path
    }

    $command = Get-Command AutoHotkey64.exe, AutoHotkey.exe, autohotkey.exe -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey64.exe"
        $candidates += Join-Path $env:ProgramFiles "AutoHotkey\AutoHotkey64.exe"
    }
    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\v2\AutoHotkey64.exe"
        $candidates += Join-Path ${env:ProgramFiles(x86)} "AutoHotkey\AutoHotkey64.exe"
    }
    if ($env:LocalAppData) {
        $candidates += Join-Path $env:LocalAppData "Programs\AutoHotkey\v2\AutoHotkey64.exe"
        $candidates += Join-Path $env:LocalAppData "Programs\AutoHotkey\AutoHotkey64.exe"
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "AutoHotkey runtime not found. Provide -AutoHotkeyPath or set AHK_BASE_FILE."
}

function Get-TestFilesForSuite {
    param(
        [Parameter(Mandatory)]
        [string]$Root,
        [Parameter(Mandatory)]
        [string]$SuiteName
    )

    $suiteDir = Join-Path $Root "tests\$SuiteName"
    if (-not (Test-Path -LiteralPath $suiteDir)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $suiteDir -Filter "*.test.ahk" -File -Recurse |
        Sort-Object FullName)
}

function ConvertTo-OutputText {
    param(
        $OutputValue
    )

    if ($null -eq $OutputValue) {
        return ""
    }

    if ($OutputValue -is [System.Array]) {
        return ($OutputValue | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    }

    return $OutputValue.ToString()
}

function Save-DesktopScreenshot {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing

        $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

        try {
            $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }

        return $Path
    } catch {
        Write-Warning "Failed to capture screenshot: $($_.Exception.Message)"
        return $null
    }
}

if (-not $OutputDir) {
    $OutputDir = Join-Path $ProjectRoot "test-results"
}

$ProjectRoot = Resolve-ExistingPath -PathValue $ProjectRoot -Label "Project root"
$OutputDir = [System.IO.Path]::GetFullPath($OutputDir)
$runtimePath = Resolve-AutoHotkeyRuntime -RequestedPath $AutoHotkeyPath
$selectedSuites = Resolve-SuiteSelection -SuiteValues $Suite

if (Test-Path -LiteralPath $OutputDir) {
    Remove-Item -LiteralPath $OutputDir -Recurse -Force
}

$null = New-Item -ItemType Directory -Path $OutputDir
$logsRoot = Join-Path $OutputDir "logs"
$screenshotsRoot = Join-Path $OutputDir "screenshots"
$null = New-Item -ItemType Directory -Path $logsRoot
$null = New-Item -ItemType Directory -Path $screenshotsRoot

$results = New-Object System.Collections.Generic.List[object]
$hasFailures = $false
$stopEarly = $false

Push-Location $ProjectRoot
try {
    Write-Host "Using AutoHotkey runtime: $runtimePath"
    Write-Host "Selected suites: $($selectedSuites -join ', ')"

    foreach ($suiteName in $selectedSuites) {
        $tests = @(Get-TestFilesForSuite -Root $ProjectRoot -SuiteName $suiteName)
        $suiteLogDir = Join-Path $logsRoot $suiteName
        $null = New-Item -ItemType Directory -Path $suiteLogDir

        if (@($tests).Count -eq 0) {
            Write-Host "No tests found for suite '$suiteName'."
            continue
        }

        foreach ($testFile in $tests) {
            $testName = [System.IO.Path]::GetFileNameWithoutExtension($testFile.Name)
            $logPath = Join-Path $suiteLogDir ($testName + ".log")
            $startTime = Get-Date
            $global:LASTEXITCODE = 0
            $output = & $runtimePath '/ErrorStdOut=UTF-8' $testFile.FullName 2>&1
            $exitCodeVar = Get-Variable LASTEXITCODE -ErrorAction SilentlyContinue
            $exitCode = if ($exitCodeVar) { [int]$exitCodeVar.Value } else { 0 }
            $durationMs = [int]((Get-Date) - $startTime).TotalMilliseconds
            $outputText = ConvertTo-OutputText -OutputValue $output

            Set-Content -LiteralPath $logPath -Value $outputText -Encoding utf8

            $screenshotPath = $null
            if ($exitCode -ne 0 -and $suiteName -eq "gui") {
                $shotName = "{0}-{1:yyyyMMdd-HHmmss}.png" -f $testName, (Get-Date)
                $screenshotPath = Save-DesktopScreenshot -Path (Join-Path $screenshotsRoot $shotName)
            }

            $status = if ($exitCode -eq 0) { "passed" } else { "failed" }
            $results.Add([pscustomobject]@{
                suite = $suiteName
                test = $testFile.Name
                path = $testFile.FullName
                status = $status
                exitCode = $exitCode
                durationMs = $durationMs
                logFile = $logPath
                screenshot = $screenshotPath
            })

            Write-Host ("[{0}] {1}/{2} ({3} ms)" -f ($status.ToUpperInvariant()), $suiteName, $testFile.Name, $durationMs)

            if ($exitCode -ne 0) {
                $hasFailures = $true
                if (-not $Ci) {
                    $stopEarly = $true
                    break
                }
            }
        }

        if ($stopEarly) {
            break
        }
    }
} finally {
    Pop-Location
}

$summaryPath = Join-Path $OutputDir "summary.json"
$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding utf8

$passedCount = @($results | Where-Object { $_.status -eq "passed" }).Count
$failedCount = @($results | Where-Object { $_.status -eq "failed" }).Count

Write-Host "Results written to $summaryPath"
Write-Host ("Summary: passed={0}, failed={1}" -f $passedCount, $failedCount)

exit ($hasFailures ? 1 : 0)
