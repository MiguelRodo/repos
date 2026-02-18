# GitHub Copilot Instructions for repos

This document provides guidance for GitHub Copilot when working with the repos tool.

## Script Architecture

### clone-repos.sh Path Logic

The `clone-repos.sh` script clones repositories to the **parent directory** of the current location.

Example:
```
workspace/
├── my-project/          # Contains repos.list
├── backend/             # Cloned here
├── frontend/            # Cloned here
```

When run from `my-project/`, repositories are cloned to the parent directory (`workspace/`).

### Fallback Repository Behavior

Lines starting with `@<branch>` use a fallback repository:
- Initially: the current repo's remote (the repo containing repos.list)
- After each line: fallback updates to the repo used by that line

This allows creating multiple worktrees from different repositories in sequence.

## repos.list Format

### Global Flags

Global flags can be specified at the start of any line in `repos.list` (with only blank space or comments after the flag):

- `--codespaces` - Enable Codespaces authentication for all repositories
- `--public` - Create all repositories as public by default
- `--private` - Create all repositories as private by default
- `--worktree` - Create all branch clones as worktrees instead of separate clones

These flags are parsed by `setup-repos.sh` and passed to the appropriate helper scripts.

### Per-Line Flags

Repository lines can include:
- `--public` or `--private` - Override the global visibility setting for that specific repository

Example repos.list:
```
--private              # Global: default to private
--codespaces           # Global: enable codespaces
myorg/repo1            # Created as private
myorg/repo2 --public   # Override: created as public
@dev                   # Branch clone
```

### Flag Precedence

1. Per-line `--public`/`--private` flags override global settings
2. Global flags in repos.list override command-line defaults
3. Command-line flags can set initial defaults

## Testing

Run tests from the `tests/` directory:
```bash
cd tests
./test-auth-check.sh
./test-setup-repos-local.sh
./test-setup-repos.sh
./test-repos-list-flags.sh
```
