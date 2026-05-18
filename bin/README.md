# Windows Binary

`repos` is a pure-Go CLI. On Windows, the installer places the compiled
`repos.exe` binary directly on your PATH.

## Usage

After running `install.ps1` from the repository root, users can run:

```powershell
repos --help
repos clone
```

## Requirements

- **Git for Windows**: Required for `git` operations performed by `repos`
