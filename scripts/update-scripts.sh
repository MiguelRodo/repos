#!/usr/bin/env bash
# update-scripts.sh — Update scripts from MiguelRodo/CompTemplate
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# This script pulls the latest scripts from the CompTemplate repository

set -Eeo pipefail

# --- Configuration ---
UPSTREAM_REPO="https://github.com/MiguelRodo/CompTemplate.git"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"
SCRIPTS_SUBDIR="scripts"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
      shift; UPSTREAM_BRANCH="$1"; shift ;;
    -n|--dry-run)
      DRY_RUN=true; shift ;;
    -f|--force)
      FORCE=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage; exit 1 ;;
  esac
done

# --- Validate environment ---
cd "$PROJECT_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a Git working tree" >&2
  exit 1
fi

# Check for uncommitted changes
if ! $FORCE && ! git diff --quiet HEAD -- "$TARGET_DIR"; then
  echo "Error: You have uncommitted changes in scripts/" >&2
  echo "Commit or stash your changes, or use --force to overwrite." >&2
  echo "" >&2
  echo "Changed files:" >&2
  git status --short "$TARGET_DIR" >&2
  exit 1
fi

# --- Create temp directory ---
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Fetching scripts from $UPSTREAM_REPO (branch: $UPSTREAM_BRANCH)..."

# --- Clone the upstream repo ---
if ! git clone --depth 1 --branch "$UPSTREAM_BRANCH" --single-branch "$UPSTREAM_REPO" "$TEMP_DIR/CompTemplate" >/dev/null 2>&1; then
  echo "Error: Failed to clone upstream repository" >&2
  echo "Repository: $UPSTREAM_REPO" >&2
  echo "Branch: $UPSTREAM_BRANCH" >&2
  exit 1
fi

UPSTREAM_SCRIPTS="$TEMP_DIR/CompTemplate/$SCRIPTS_SUBDIR"

if [ ! -d "$UPSTREAM_SCRIPTS" ]; then
  echo "Error: Scripts directory not found in upstream repo: $SCRIPTS_SUBDIR" >&2
  exit 1
fi

# --- List files to update ---
echo ""
echo "Files to update:"
SCRIPT_COUNT=0

# Function to recursively list and count files
list_scripts() {
  local src_dir="$1"
  local dst_dir="$2"
  local rel_path="$3"
  
  for item in "$src_dir"/*; do
    [ ! -e "$item" ] && continue
    
    local item_name="$(basename "$item")"
    local rel_item="${rel_path:+$rel_path/}$item_name"
    
    if [ -d "$item" ]; then
      # Recursively process subdirectories
      list_scripts "$item" "$dst_dir/$item_name" "$rel_item"
    elif [ -f "$item" ]; then
      # Compare files
      if [ -f "$dst_dir/$item_name" ]; then
        if ! diff -q "$item" "$dst_dir/$item_name" >/dev/null 2>&1; then
          echo "  ✓ $rel_item (modified)"
          SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
        else
          echo "  = $rel_item (unchanged)"
        fi
      else
        echo "  + $rel_item (new)"
        SCRIPT_COUNT=$((SCRIPT_COUNT + 1))
      fi
    fi
  done
}

list_scripts "$UPSTREAM_SCRIPTS" "$TARGET_DIR" ""

if [ "$SCRIPT_COUNT" -eq 0 ]; then
  echo ""
  echo "✓ All scripts are up to date!"
  exit 0
fi

if $DRY_RUN; then
  echo ""
  echo "This was a dry run. Use without --dry-run to apply changes."
  exit 0
fi

# --- Prompt for confirmation ---
if ! $FORCE; then
  echo ""
  read -p "Update $SCRIPT_COUNT script(s)? [y/N] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Update cancelled."
    exit 0
  fi
fi

# --- Copy scripts ---
echo ""
echo "Updating scripts..."

# Function to recursively copy files
copy_scripts() {
  local src_dir="$1"
  local dst_dir="$2"
  local rel_path="$3"
  
  for item in "$src_dir"/*; do
    [ ! -e "$item" ] && continue
    
    local item_name="$(basename "$item")"
    local rel_item="${rel_path:+$rel_path/}$item_name"
    
    if [ -d "$item" ]; then
      # Create directory if needed
      mkdir -p "$dst_dir/$item_name"
      # Recursively copy subdirectories
      copy_scripts "$item" "$dst_dir/$item_name" "$rel_item"
    elif [ -f "$item" ]; then
      # Copy file and preserve permissions
      cp "$item" "$dst_dir/$item_name"
      chmod +x "$dst_dir/$item_name"
      echo "  ✓ Updated $rel_item"
    fi
  done
}

copy_scripts "$UPSTREAM_SCRIPTS" "$TARGET_DIR" ""

# --- Commit changes ---
echo ""
echo "Committing changes..."

git add "$TARGET_DIR"

if git diff --staged --quiet; then
  echo "No changes to commit (files may be identical)."
else
  COMMIT_MSG="Update scripts from CompTemplate@$UPSTREAM_BRANCH

Updated scripts in scripts/ from:
Repository: $UPSTREAM_REPO
Branch: $UPSTREAM_BRANCH
Date: $(date -u +%Y-%m-%d)"
  
  git commit -m "$COMMIT_MSG"
  
  echo ""
  echo "✅ Scripts updated successfully!"
  echo ""
  echo "Changes committed. Review with:"
  echo "  git show HEAD"
  echo ""
  echo "Push when ready:"
  echo "  git push"
fi
