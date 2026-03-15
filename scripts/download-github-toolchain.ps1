param(
    [string]$AutoHotkeyVersion,
    [string]$Ahk2ExeVersion,
    [string]$OutputRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GitHubApiHeaders {
    $headers = @{
        Accept = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
    }

    if ($env:GITHUB_TOKEN) {
        $headers["Authorization"] = "Bearer $env:GITHUB_TOKEN"
    }

    return $headers
}

function Get-GitHubUserAgent {
    return "AHKeyMap-GitHubToolchain"
}

function Get-HttpStatusCode {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord
    )

    $response = $ErrorRecord.Exception.Response
    if ($null -eq $response) {
        return $null
    }

    try {
        return [int]$response.StatusCode
    } catch {
        try {
            return [int]$response.StatusCode.value__
        } catch {
            return $null
        }
    }
}

function Get-ReleaseByTag {
    param(
        [Parameter(Mandatory)]
        [string]$Owner,
        [Parameter(Mandatory)]
        [string]$Repo,
        [Parameter(Mandatory)]
        [string]$Tag,
        [switch]$AllowMissing
    )

    $repoPath = "{0}/{1}" -f $Owner, $Repo
    $uri = "https://api.github.com/repos/{0}/releases/tags/{1}" -f $repoPath, $Tag
    try {
        $release = Invoke-RestMethod `
            -Uri $uri `
            -Headers (Get-GitHubApiHeaders) `
            -UserAgent (Get-GitHubUserAgent)
        Write-Host ("Resolved release tag {0} for {1} as {2}" -f $Tag, $repoPath, $release.tag_name)
        return $release
    } catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        if ($AllowMissing -and $statusCode -eq 404) {
            Write-Host ("Release tag not found for {0}: {1}" -f $repoPath, $Tag)
            return $null
        }

        throw ("Failed to query release tag {0} for {1}. Status: {2}. {3}" -f $Tag, $repoPath, $statusCode, $_.Exception.Message)
    }
}

function Format-AssetList {
    param(
        [Parameter(Mandatory)]
        [object[]]$Assets
    )

    if ($Assets.Count -eq 0) {
        return "(no assets)"
    }

    return ($Assets | ForEach-Object { "- $($_.name)" }) -join "`n"
}

function Select-ReleaseAsset {
    param(
        [Parameter(Mandatory)]
        [object]$Release,
        [string[]]$PreferredNames = @(),
        [string]$RegexPattern = ""
    )

    $assets = @($Release.assets)
    if ($assets.Count -eq 0) {
        throw "Release $($Release.tag_name) has no assets."
    }

    foreach ($name in $PreferredNames) {
        $match = $assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if ($match) {
            Write-Host "Selected asset from $($Release.tag_name): $($match.name)"
            return $match
        }
    }

    if ($RegexPattern) {
        $match = $assets | Where-Object { $_.name -match $RegexPattern } | Select-Object -First 1
        if ($match) {
            Write-Host "Selected asset from $($Release.tag_name): $($match.name)"
            return $match
        }
    }

    throw "No matching asset found in release $($Release.tag_name). Available assets:`n$(Format-AssetList -Assets $assets)"
}

function Download-ReleaseAsset {
    param(
        [Parameter(Mandatory)]
        [object]$Asset,
        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $headers = Get-GitHubApiHeaders
    $headers["Accept"] = "application/octet-stream"

    Write-Host "Downloading asset $($Asset.name)"
    Invoke-WebRequest `
        -Uri $Asset.url `
        -Headers $headers `
        -UserAgent (Get-GitHubUserAgent) `
        -OutFile $DestinationPath
}

function Write-OutputVariable {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [string]$Value
    )

    if ($env:GITHUB_ENV) {
        "$Name=$Value" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
    } else {
        Write-Host "$Name=$Value"
    }
}

if (-not $OutputRoot) {
    $baseTemp = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
    $OutputRoot = Join-Path $baseTemp "ahk-toolchain"
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

$autoHotkeyRelease = Get-ReleaseByTag -Owner "AutoHotkey" -Repo "AutoHotkey" -Tag "v$AutoHotkeyVersion"
$autoHotkeyAsset = Select-ReleaseAsset `
    -Release $autoHotkeyRelease `
    -PreferredNames @("AutoHotkey_$AutoHotkeyVersion.zip")

$autoHotkeyZip = Join-Path $OutputRoot $autoHotkeyAsset.name
Download-ReleaseAsset -Asset $autoHotkeyAsset -DestinationPath $autoHotkeyZip
Expand-Archive -LiteralPath $autoHotkeyZip -DestinationPath $autoHotkeyRoot -Force

$baseFile = Get-ChildItem -Path $autoHotkeyRoot -Recurse -Filter AutoHotkey64.exe | Select-Object -First 1
if (-not $baseFile) {
    throw "AutoHotkey64.exe not found after extracting AutoHotkey runtime"
}

$ahk2ExeRelease = Get-ReleaseByTag -Owner "AutoHotkey" -Repo "Ahk2Exe" -Tag "Ahk2Exe$Ahk2ExeVersion" -AllowMissing
if (-not $ahk2ExeRelease) {
    $ahk2ExeRelease = Get-ReleaseByTag -Owner "AutoHotkey" -Repo "Ahk2Exe" -Tag "v$Ahk2ExeVersion"
}

$ahk2ExeAsset = Select-ReleaseAsset `
    -Release $ahk2ExeRelease `
    -PreferredNames @("Ahk2Exe.exe", "Ahk2Exe.zip") `
    -RegexPattern "^Ahk2Exe.*\.zip$"

$ahk2ExeDownloadPath = Join-Path $ahk2ExeRoot $ahk2ExeAsset.name
Download-ReleaseAsset -Asset $ahk2ExeAsset -DestinationPath $ahk2ExeDownloadPath

if ($ahk2ExeDownloadPath -match "\.zip$") {
    Expand-Archive -LiteralPath $ahk2ExeDownloadPath -DestinationPath $compilerDir -Force
} else {
    Copy-Item -LiteralPath $ahk2ExeDownloadPath -Destination (Join-Path $compilerDir "Ahk2Exe.exe") -Force
}

$ahk2ExeExe = Get-ChildItem -Path $compilerDir -Recurse -Filter Ahk2Exe.exe | Select-Object -First 1
if (-not $ahk2ExeExe) {
    throw "Ahk2Exe.exe not found after download"
}

Write-OutputVariable -Name "AHK2EXE_PATH" -Value $ahk2ExeExe.FullName
Write-OutputVariable -Name "AHK_BASE_FILE" -Value $baseFile.FullName
