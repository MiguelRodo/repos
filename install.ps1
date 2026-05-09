#!/usr/bin/env pwsh
# install.ps1 - Install repos CLI binary into a writable directory already in PATH

param(
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

function Get-ArchName {
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    switch ($arch.ToString()) {
        "X64" { return "amd64" }
        "Arm64" { return "arm64" }
        default { throw "Unsupported architecture: $arch" }
    }
}

function Test-WritableDirectory([string]$PathEntry) {
    if ([string]::IsNullOrWhiteSpace($PathEntry) -or -not (Test-Path -LiteralPath $PathEntry -PathType Container)) {
        return $false
    }
    try {
        $probe = Join-Path $PathEntry ".repos-write-test-$([guid]::NewGuid().ToString()).tmp"
        Set-Content -LiteralPath $probe -Value "ok" -Encoding ascii
        Remove-Item -LiteralPath $probe -Force
        return $true
    } catch {
        return $false
    }
}

function Get-WritablePathDirectory {
    $pathEntries = $env:Path -split ';'
    foreach ($entry in $pathEntries) {
        if (Test-WritableDirectory $entry) {
            return $entry
        }
    }
    throw "No writable directory found in PATH."
}

if ($Uninstall) {
    $removed = $false
    foreach ($entry in ($env:Path -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $candidate = Join-Path $entry "repos.exe"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            try {
                Remove-Item -LiteralPath $candidate -Force
                Write-Host "Removed $candidate" -ForegroundColor Green
                $removed = $true
            } catch {
                Write-Warning "Could not remove ${candidate}: $($_.Exception.Message)"
            }
        }
    }

    if (-not $removed) {
        Write-Host "No repos.exe found in PATH directories." -ForegroundColor Yellow
    }
    exit 0
}

$releaseRepo = if ($env:REPOS_RELEASE_REPO) { $env:REPOS_RELEASE_REPO } else { "miguelrodo/repos-go" }
$binaryName = if ($env:REPOS_BINARY_NAME) { $env:REPOS_BINARY_NAME } else { "repos" }
$osName = "windows"
$archName = Get-ArchName
$installDir = Get-WritablePathDirectory
$downloadBase = "https://github.com/$releaseRepo/releases/latest/download"
$tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) "$binaryName-$PID.exe"

$assets = @(
    "$binaryName-$osName-$archName.exe",
    "$binaryName" + "_" + "$osName" + "_" + "$archName.exe"
)

$downloadedAsset = $null
foreach ($asset in $assets) {
    $url = "$downloadBase/$asset"
    Write-Host "Trying $url..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmpFile
        $downloadedAsset = $asset
        break
    } catch {
    }
}

if (-not $downloadedAsset) {
    throw "Could not download a release asset for $osName/$archName. Tried: $($assets -join ', ') from $downloadBase"
}

$target = Join-Path $installDir "$binaryName.exe"
Move-Item -LiteralPath $tmpFile -Destination $target -Force
Write-Host "Installed $binaryName ($downloadedAsset) to $target" -ForegroundColor Green
Write-Host "Run: $binaryName --help"
