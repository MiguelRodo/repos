#!/usr/bin/env bash
# update-branches.sh — Update all worktrees with latest devcontainer prebuild
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# This script updates .devcontainer/devcontainer.json in all worktrees
# with the content from .devcontainer/prebuild/devcontainer.json in the base repo

set -Eeo pipefail

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Usage ---
usage() {
  cat <<EOF
Usage: $0 [options]

Update all worktrees with the latest devcontainer prebuild configuration.

This script:
  1. Reads .devcontainer/prebuild/devcontainer.json from the base repo
  2. Strips the codespaces repositories section
  3. Writes to .devcontainer/devcontainer.json in each worktree
  4. Commits and pushes changes to each worktree

Options:
  -n, --dry-run    Show what would be done without making changes
  -h, --help       Show this message

Prerequisites:
  - .devcontainer/prebuild/devcontainer.json must exist in base repo
  - jq or python3 must be available for JSON manipulation

Examples:
  $0              # Update all worktrees
  $0 --dry-run    # Preview updates without making changes

Notes:
  - Worktrees are identified using 'git worktree list'
  - Only worktrees (not the base repo) are updated
  - Each update is committed and pushed automatically
EOF
}

# --- Parse arguments ---
DRY_RUN=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--dry-run)
      DRY_RUN=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

# --- Validate ---
cd "$PROJECT_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a Git working tree" >&2
  exit 1
fi

PREBUILD_FILE="$PROJECT_ROOT/.devcontainer/prebuild/devcontainer.json"

if [ ! -f "$PREBUILD_FILE" ]; then
  echo "Error: prebuild devcontainer not found: $PREBUILD_FILE" >&2
  echo "This file is required to update worktrees." >&2
  exit 1
fi

# --- Check for JSON tools ---
if command -v jq >/dev/null 2>&1; then
  JSON_TOOL="jq"
elif command -v python3 >/dev/null 2>&1; then
  JSON_TOOL="python3"
else
  echo "Error: Neither jq nor python3 found. One is required for JSON manipulation." >&2
  exit 1
fi

# --- Process worktrees ---
echo "Finding worktrees..."

# Get worktree list (skip the base repo)
WORKTREE_COUNT=0
UPDATED_COUNT=0
SKIPPED_COUNT=0

while IFS= read -r line; do
  # Parse worktree line: "path commit [branch]"
  WORKTREE_PATH="${line%% *}"
  
  # Skip the base repo (it will have bare or the repo path)
  if [ "$WORKTREE_PATH" = "$PROJECT_ROOT" ]; then
    continue
  fi
  
  WORKTREE_COUNT=$((WORKTREE_COUNT + 1))
  
  echo ""
  echo "[$WORKTREE_COUNT] $(basename "$WORKTREE_PATH")"
  echo "    Path: $WORKTREE_PATH"
  
  # Check if worktree has .devcontainer directory
  if [ ! -d "$WORKTREE_PATH/.devcontainer" ]; then
    echo "    ⏭  No .devcontainer directory, skipping"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    continue
  fi
  
  DEST_FILE="$WORKTREE_PATH/.devcontainer/devcontainer.json"
  
  if $DRY_RUN; then
    echo "    DRY-RUN: Would update $DEST_FILE"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
    continue
  fi
  
  # Read and process the prebuild file
  if [ "$JSON_TOOL" = "jq" ]; then
    jq 'del(.customizations.codespaces.repositories)' "$PREBUILD_FILE" > "$DEST_FILE.tmp"
  else
    python3 -c "
import json, sys
with open('$PREBUILD_FILE') as f:
    data = json.load(f)
if 'customizations' in data and 'codespaces' in data['customizations']:
    if 'repositories' in data['customizations']['codespaces']:
        del data['customizations']['codespaces']['repositories']
with open('$DEST_FILE.tmp', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
  fi
  
  # Move the temp file to destination
  mv "$DEST_FILE.tmp" "$DEST_FILE"
  
  echo "    ✓ Updated devcontainer.json"
  
  # Commit and push
  cd "$WORKTREE_PATH"
  
  if git diff --quiet "$DEST_FILE"; then
    echo "    ℹ️  No changes to commit"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  else
    git add ".devcontainer/devcontainer.json"
    git commit -m "Update devcontainer from latest prebuild"
    
    # Get current branch
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    git push origin "$BRANCH" || echo "    ⚠️  Push failed (you may need to push manually)"
    
    echo "    ✓ Committed and pushed"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  fi
  
  cd "$PROJECT_ROOT"
  
done < <(git worktree list --porcelain | grep '^worktree' | sed 's/^worktree //')

echo ""
echo "Summary:"
echo "  Worktrees found: $WORKTREE_COUNT"
echo "  Updated: $UPDATED_COUNT"
echo "  Skipped: $SKIPPED_COUNT"

if $DRY_RUN; then
  echo ""
  echo "This was a dry run. Use without --dry-run to apply changes."
fi
