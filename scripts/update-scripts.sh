#!/usr/bin/env bash
# update-scripts.sh — Update scripts from MiguelRodo/CompTemplate
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# This script pulls the latest scripts from the CompTemplate repository

set -Eeuo pipefail

# Never prompt for credentials (prevents stdin reads that can kill the loop)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

git() { command git "$@" </dev/null; }

# --- Configuration ---
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/MiguelRodo/CompTemplate.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
SCRIPTS_SUBDIR="scripts"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="$SCRIPT_DIR"

# --- Usage ---
usage() {
  cat <<EOF
Usage: $0 [options]

Update scripts from the upstream CompTemplate repository.

This script:
  1. Clones/pulls the latest MiguelRodo/CompTemplate repository
  2. Copies all scripts from scripts/ directory (including helper/ subdirectory)
  3. Preserves executable permissions
  4. Creates a commit with the updates

Options:
  -b, --branch <name>  Use specific branch (default: main)
  -n, --dry-run        Show what would be updated without making changes
  -f, --force          Overwrite local changes without prompting
  -h, --help           Show this message

Environment Variables:
  UPSTREAM_BRANCH      Override the default branch (default: main)

Examples:
  $0                    # Update from main branch
  $0 --branch dev       # Update from dev branch
  $0 --dry-run          # Preview updates
  $0 --force            # Force update without prompts

Notes:
  - Updates all files in scripts/ directory (including helper/ subdirectory)
  - Preserves local modifications to other files
  - Creates a git commit with the changes
EOF
}

# --- Parse arguments ---
DRY_RUN=false
FORCE=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -b|--branch)
      shift; [ $# -gt 0 ] || usage; UPSTREAM_BRANCH="$1"; shift ;;
    -n|--dry-run)
      DRY_RUN=true; shift ;;
    -f|--force)
      FORCE=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      printf "Error: Unknown option: %s\n" "$1" >&2
      usage; exit 1 ;;
  esac
done

# Validate upstream branch name
if ! git check-ref-format --allow-onelevel "$UPSTREAM_BRANCH" || [[ "$UPSTREAM_BRANCH" == -* ]]; then
  printf "Error: '%s' is not a valid Git branch name.\n" "$UPSTREAM_BRANCH" >&2
  exit 1
fi

# --- Validate environment ---
cd "$PROJECT_ROOT"

# Handle 'dubious ownership' errors in CI containers by marking the directory as safe
if [ -d ".git" ]; then
  git config --global --add safe.directory "$(pwd)" 2>/dev/null || true
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf 'Error: not inside a Git working tree\n' >&2
  exit 1
fi

# Check for uncommitted changes
# Use -- separator for git diff to handle paths correctly
if ! $FORCE && ! git diff --quiet HEAD -- "$TARGET_DIR"; then
  printf 'Error: You have uncommitted changes in scripts/\n' >&2
  printf 'Commit or stash your changes, or use --force to overwrite.\n' >&2
  printf '\n' >&2
  printf 'Changed files:\n' >&2
  git status --short -- "$TARGET_DIR" >&2
  exit 1
fi

# --- Create temp directory ---
# Use mktemp without -- for portability with BSD/macOS
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT

printf 'Fetching scripts from %s (branch: %s)...\n' "$UPSTREAM_REPO" "$UPSTREAM_BRANCH"

# --- Clone the upstream repo ---
# Use -- separator to ensure arguments are not misinterpreted as options
if ! git clone --depth 1 --branch "$UPSTREAM_BRANCH" --single-branch -- "$UPSTREAM_REPO" "$TEMP_DIR/CompTemplate"; then
  printf 'Error: Failed to clone upstream repository\n' >&2
  printf 'Repository: %s\n' "$UPSTREAM_REPO" >&2
  printf 'Branch: %s\n' "$UPSTREAM_BRANCH" >&2
  exit 1
fi

UPSTREAM_SCRIPTS="$TEMP_DIR/CompTemplate/$SCRIPTS_SUBDIR"

if [ ! -d "$UPSTREAM_SCRIPTS" ]; then
  printf 'Error: Scripts directory not found in upstream repo: %s\n' "$SCRIPTS_SUBDIR" >&2
  exit 1
fi

# --- List files to update ---
printf '\n'
printf 'Files to update:\n'
SCRIPT_COUNT=0

# Function to recursively list and count files
list_scripts() {
  local src_dir="$1"
  local dst_dir="$2"
  local rel_path="$3"
  
  for item in "$src_dir"/*; do
    [ ! -e "$item" ] && continue
    
    local item_name
    item_name="$(basename -- "$item")"
    local rel_item="${rel_path:+$rel_path/}$item_name"
    
    if [ -d "$item" ]; then
      # Recursively process subdirectories
      list_scripts "$item" "$dst_dir/$item_name" "$rel_item"
    elif [ -f "$item" ]; then
      if [ -f "$dst_dir/$item_name" ]; then
        if ! diff -q -- "$item" "$dst_dir/$item_name" >/dev/null 2>&1; then
          printf '  ✓ %s (modified)\n' "$rel_item"
          SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
        else
          printf '  = %s (unchanged)\n' "$rel_item"
        fi
      else
        printf '  + %s (new)\n' "$rel_item"
        SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
      fi
    fi
  done
}

list_scripts "$UPSTREAM_SCRIPTS" "$TARGET_DIR" ""

if [ "$SCRIPT_COUNT" -eq 0 ]; then
  printf '\n'
  printf '✓ All scripts are up to date!\n'
  exit 0
fi

if $DRY_RUN; then
  printf '\n'
  printf 'This was a dry run. Use without --dry-run to apply changes.\n'
  exit 0
fi

# --- Prompt for confirmation ---
if ! $FORCE; then
  printf '\n'
  # Use printf for the prompt and read for the response
  printf 'Update %d script(s)? [y/N] ' "$SCRIPT_COUNT"
  read -n 1 -r
  printf '\n'
  if [[ ! ${REPLY:-N} =~ ^[Yy]$ ]]; then
    printf 'Update cancelled.\n'
    exit 0
  fi
fi

# --- Copy scripts ---
printf '\n'
printf 'Updating scripts...\n'

# Function to recursively copy files
copy_scripts() {
  local src_dir="$1"
  local dst_dir="$2"
  local rel_path="$3"
  
  for item in "$src_dir"/*; do
    [ ! -e "$item" ] && continue
    
    local item_name
    item_name="$(basename -- "$item")"
    local rel_item="${rel_path:+$rel_path/}$item_name"
    
    if [ -d "$item" ]; then
      # Create directory if needed
      mkdir -p -- "$dst_dir/$item_name"
      # Recursively copy subdirectories
      copy_scripts "$item" "$dst_dir/$item_name" "$rel_item"
    elif [ -f "$item" ]; then
      # Copy file and preserve permissions
      cp -- "$item" "$dst_dir/$item_name"
      chmod -- +x "$dst_dir/$item_name"
      printf '  ✓ Updated %s\n' "$rel_item"
    fi
  done
}

copy_scripts "$UPSTREAM_SCRIPTS" "$TARGET_DIR" ""

# --- Commit changes ---
printf '\n'
printf 'Committing changes...\n'

# Use -- separator for git add to handle paths correctly
git add -- "$TARGET_DIR"

if git diff --staged --quiet; then
  printf 'No changes to commit (files may be identical).\n'
else
  COMMIT_MSG="Update scripts from CompTemplate@$UPSTREAM_BRANCH

Updated scripts in scripts/ from:
Repository: $UPSTREAM_REPO
Branch: $UPSTREAM_BRANCH
Date: $(date -u +%Y-%m-%d)"
  
  # Use -- for commit message to avoid potential issues
  git commit -m "$COMMIT_MSG" --
  
  printf '\n'
  printf '✅ Scripts updated successfully!\n'
  printf '\n'
  printf 'Changes committed. Review with:\n'
  printf '  git show HEAD\n'
  printf '\n'
  printf 'Push when ready:\n'
  printf '  git push\n'
fi
