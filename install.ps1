#!/usr/bin/env pwsh
# install.ps1 - Install repos tool for Windows (Manual Installation)
# This script adds the bin/ directory to the user's PATH

param(
    [switch]$Uninstall
)

# Determine the absolute path to the bin directory
$ScriptRoot = Split-Path -Parent $PSCommandPath
$BinDir = Join-Path $ScriptRoot "bin"

# Verify bin directory exists
if (-not (Test-Path $BinDir)) {
    Write-Error "Error: bin directory not found at $BinDir"
    exit 1
}

# Get the current user PATH
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

if ($Uninstall) {
    # Remove from PATH
    if ($UserPath -like "*$BinDir*") {
        $NewPath = ($UserPath -split ';' | Where-Object { $_ -ne $BinDir }) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        Write-Host "Successfully removed $BinDir from PATH" -ForegroundColor Green
        Write-Host "Please restart your PowerShell session for changes to take effect." -ForegroundColor Yellow
    } else {
        Write-Host "repos bin directory was not found in PATH." -ForegroundColor Yellow
    }
} else {
    # Add to PATH
    if ($UserPath -like "*$BinDir*") {
        Write-Host "repos bin directory is already in PATH." -ForegroundColor Yellow
    } else {
        $NewPath = "$UserPath;$BinDir"
        [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
        Write-Host "Successfully added $BinDir to PATH" -ForegroundColor Green
        Write-Host "Please restart your PowerShell session for changes to take effect." -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Installation complete!" -ForegroundColor Green
Write-Host ""
Write-Host "After restarting PowerShell, you can run:" -ForegroundColor Cyan
Write-Host "  repos --help" -ForegroundColor White
Write-Host ""
Write-Host "Dependencies required:" -ForegroundColor Cyan
Write-Host "  - Git for Windows (includes bash, git, curl)" -ForegroundColor White
Write-Host "  - jq (download from https://jqlang.github.io/jq/download/)" -ForegroundColor White
Write-Host ""
