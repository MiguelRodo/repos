#!/usr/bin/env pwsh
# repos.ps1 - Multi-repository management tool wrapper for Windows
# This script launches setup-repos.sh or run-pipeline.sh using Git Bash

$Usage = @"
Usage: repos <command> [options]

Commands:
  setup    Clone and configure repositories from a repos.list file
  run      Execute a script inside each cloned repository

Run 'repos <command> --help' for more information on a command.
"@

# Determine the absolute path to the scripts directory
$ScriptRoot = Split-Path -Parent $PSCommandPath
$ScriptsDir = Join-Path (Split-Path -Parent $ScriptRoot) "scripts"

$SubcommandScripts = @{
    "setup" = "setup-repos.sh"
    "run"   = "run-pipeline.sh"
}

# Parse subcommand
if ($args.Count -eq 0 -or $args[0] -eq "--help" -or $args[0] -eq "-h") {
    Write-Output $Usage
    if ($args.Count -eq 0) { exit 1 } else { exit 0 }
}

$Subcommand = $args[0]
$Remaining = $args[1..($args.Count - 1)]

if (-not $SubcommandScripts.ContainsKey($Subcommand)) {
    Write-Error "Error: unknown command '$Subcommand'"
    Write-Output ""
    Write-Output $Usage
    exit 1
}

$TargetScript = Join-Path $ScriptsDir $SubcommandScripts[$Subcommand]

# Verify the target script exists
if (-not (Test-Path $TargetScript)) {
    Write-Error "Error: $($SubcommandScripts[$Subcommand]) not found at $TargetScript"
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
$TargetScriptUnix = $TargetScript -replace '\\', '/'
if ($TargetScriptUnix -match '^([A-Za-z]):(.*)$') {
    $Drive = $matches[1].ToLower()
    $Path = $matches[2]
    $TargetScriptUnix = "/$Drive$Path"
}

# Execute the target script with remaining arguments
& $BashPath -c "$TargetScriptUnix $Remaining"
exit $LASTEXITCODE
