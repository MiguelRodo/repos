#!/usr/bin/env pwsh
# repos.ps1 - Multi-repository management tool wrapper for Windows
# This script launches setup-repos.sh using Git Bash

# Determine the absolute path to the scripts directory
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ScriptsDir = Join-Path (Split-Path -Parent $ScriptRoot) "scripts"
$SetupScript = Join-Path $ScriptsDir "setup-repos.sh"

# Verify the setup script exists
if (-not (Test-Path $SetupScript)) {
    Write-Error "Error: setup-repos.sh not found at $SetupScript"
    Write-Error "The repos package may not be installed correctly."
    exit 1
}

# Find bash.exe (Git Bash)
$BashPath = $null
$PossiblePaths = @(
    "${env:ProgramFiles}\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "${env:LOCALAPPDATA}\Programs\Git\bin\bash.exe"
)

foreach ($Path in $PossiblePaths) {
    if (Test-Path $Path) {
        $BashPath = $Path
        break
    }
}

if (-not $BashPath) {
    # Try to find bash in PATH
    $BashPath = (Get-Command bash.exe -ErrorAction SilentlyContinue).Source
}

if (-not $BashPath) {
    Write-Error "Error: bash.exe (Git Bash) not found."
    Write-Error "Please install Git for Windows from https://git-scm.com/download/win"
    exit 1
}

# Convert Windows path to Unix-style path for Git Bash
$SetupScriptUnix = $SetupScript -replace '\\', '/'
if ($SetupScriptUnix -match '^([A-Za-z]):(.*)$') {
    $Drive = $matches[1].ToLower()
    $Path = $matches[2]
    $SetupScriptUnix = "/$Drive$Path"
}

# Execute setup-repos.sh with all passed arguments
& $BashPath -c "$SetupScriptUnix $args"
exit $LASTEXITCODE
