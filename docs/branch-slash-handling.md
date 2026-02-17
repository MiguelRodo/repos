# Branch Slash Handling

## Overview

The CompTemplate scripts now fully support branch names containing forward slashes (e.g., `feature/new-thing`, `release/v1.0.0`). This is a common pattern in popular git workflows like git-flow and GitHub Flow.

## The Problem

Branch names with slashes are valid in git but cause issues when used directly in filesystem paths.

## The Solution

The scripts now **sanitize** branch names when constructing directory paths by replacing forward slashes (`/`) with dashes (`-`), while preserving the original branch names for all git operations.

## Examples

- Branch: `feature/new-thing` → Directory: `workspace-feature-new-thing/`
- Branch: `release/v1.0.0` → Directory: `projr-release-v1.0.0/`

## Testing

Run the test suites:
```bash
bash tests/test-branch-with-slashes.sh        # Unit tests
bash tests/test-integration-branch-slashes.sh # Integration tests
bash tests/manual-test-branch-slashes.sh      # Manual demonstration
```

All tests pass successfully! ✅
