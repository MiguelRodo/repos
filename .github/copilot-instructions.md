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

## Testing

Run tests from the `tests/` directory:
```bash
cd tests
./test-auth-check.sh
./test-setup-repos-local.sh
./test-setup-repos.sh
```
