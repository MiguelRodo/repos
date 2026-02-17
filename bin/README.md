# Windows Binary Wrapper

This directory contains the PowerShell wrapper script for Windows users.

## repos.ps1

The `repos.ps1` script is a PowerShell wrapper that:

1. Locates the `scripts/setup-repos.sh` script relative to its location
2. Finds Git Bash (`bash.exe`) on the system
3. Converts Windows paths to Unix-style paths
4. Executes `setup-repos.sh` with all provided arguments

## Usage

### With Manual Installation

After running `install.ps1` from the repository root, users can run:

```powershell
repos --help
repos -f my-repos.list
```

### With Scoop

Scoop automatically configures the PATH, so users can simply run:

```powershell
repos --help
```

## Requirements

- **Git for Windows**: Provides `bash.exe` and other Unix tools
- **PowerShell**: Version 5.1 or later (included with Windows 10+)

## Path Resolution

The script searches for Git Bash in these locations (in order):

1. `C:\Program Files\Git\bin\bash.exe`
2. `C:\Program Files (x86)\Git\bin\bash.exe`
3. `%LOCALAPPDATA%\Programs\Git\bin\bash.exe`
4. System PATH

## Troubleshooting

If the script cannot find bash:
```powershell
# Verify Git for Windows is installed
git --version

# Check bash location
where bash
```
