#!/usr/bin/env bash
# add-branch.sh — Create a new worktree/branch off the current repository
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# This script:
# 1. Creates a new worktree (default) or branch off the current repo
# 2. Cleans the new worktree to minimal infrastructure
# 3. Moves .devcontainer/prebuild/devcontainer.json → .devcontainer/devcontainer.json
# 4. Strips unnecessary codespaces auth from the devcontainer.json
# 5. Adds the new branch to repos.list
# 6. Updates the workspace file

set -Eeuo pipefail

# Never prompt for credentials (prevents stdin reads that can kill the loop)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

git() { command git "$@" </dev/null; }

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Usage ---
usage() {
  cat <<EOF
Usage: $0 <branch-name> [target-directory] [options]

Create a new worktree/branch off the current repository with minimal infrastructure.

Arguments:
  branch-name          Name of the new branch to create
  target-directory     Optional: custom directory name (default: <repo>-<branch>)

Options:
  -b, --branch         Create as a separate branch instead of worktree (not recommended)
  -h, --help           Show this message

What this script does:
  1. Creates a new worktree at ../<repo>-<branch> (or ../target-directory)
  2. Pushes the branch to origin with tracking
  3. Cleans the worktree (keeps only .devcontainer/devcontainer.json and .gitignore)
  4. Moves .devcontainer/prebuild/devcontainer.json → .devcontainer/devcontainer.json
  5. Strips codespaces repositories config from devcontainer.json
  6. Adds @<branch> line to repos.list
  7. Runs vscode-workspace-add.sh to update workspace

The resulting worktree can be opened independently in VS Code/Codespaces.

Examples:
  $0 data-tidy              # Create worktree at ../CompTemplate-data-tidy
  $0 analysis my-analysis   # Create worktree at ../my-analysis
  $0 paper --branch         # Create as branch (not worktree)

Notes:
  - Worktrees share .git with the base repo (saves space, simplifies updates)
  - Each worktree can only have one branch checked out at a time
  - Deleting a worktree: git worktree remove <path>
EOF
}

# --- Parse arguments ---
BRANCH_NAME=""
TARGET_DIR=""
USE_BRANCH=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    -b|--branch)
      USE_BRANCH=true; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    -*)
      # If it starts with - and isn't a known flag or after --, it's an error.
      # But we need to distinguish between an actual flag and a positional
      # argument that *could* be a branch name but starts with -.
      # Standard practice is that everything after the first non-option is a positional
      # argument, unless options are allowed anywhere.
      # In our case, we'll be strict: if it starts with -, it's an option.
      # If you want a branch name starting with -, you MUST use --.
      printf "Error: Unknown option: %s\n" "$1" >&2
      usage; exit 1 ;;
    *)
      if [ -z "$BRANCH_NAME" ]; then
        BRANCH_NAME="$1"
      elif [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$1"
      else
        printf "Error: Too many arguments: %s\n" "$1" >&2
        usage; exit 1
      fi
      shift ;;
  esac
done

# Process remaining positional arguments after --
while [ "$#" -gt 0 ]; do
  if [ -z "$BRANCH_NAME" ]; then
    BRANCH_NAME="$1"
  elif [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$1"
  else
    printf "Error: Too many arguments: %s\n" "$1" >&2
    usage; exit 1
  fi
  shift
done

if [ -z "$BRANCH_NAME" ]; then
  printf "Error: branch-name is required\n" >&2
  usage
  exit 1
fi

# Validate branch name
if ! git check-ref-format --allow-onelevel "$BRANCH_NAME" || [[ "$BRANCH_NAME" == -* ]]; then
  printf "Error: '%s' is not a valid Git branch name.\n" "$BRANCH_NAME" >&2
  exit 1
fi

# --- Validate we're in a git repo ---
cd -- "$PROJECT_ROOT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  printf "Error: not inside a Git working tree\n" >&2
  exit 1
fi

# Sanitize branch name for use in directory paths
# Replaces forward slashes with dashes to avoid nested directories
sanitize_branch_name() {
  local branch="$1"
  printf '%s\n' "${branch//\//-}"
}

# --- Determine destination ---
REPO_NAME="$(basename -- "$PROJECT_ROOT")"
PARENT_DIR="$(dirname -- "$PROJECT_ROOT")"

if [ -n "$TARGET_DIR" ]; then
  # Validate TARGET_DIR to prevent path traversal and argument injection
  case "$TARGET_DIR" in
    /*|*..*|-*)
      printf "Error: target directory cannot be absolute, contain '..', or start with a hyphen: %s\n" "$TARGET_DIR" >&2
      exit 1
      ;;
  esac
  DEST="$PARENT_DIR/$TARGET_DIR"
else
  SAFE_BRANCH_NAME="$(sanitize_branch_name "$BRANCH_NAME")"
  DEST="$PARENT_DIR/${REPO_NAME}-${SAFE_BRANCH_NAME}"
fi

printf 'Creating worktree: %s\n' "$DEST"
printf '  Branch: %s\n' "$BRANCH_NAME"
printf '  Base repo: %s\n' "$PROJECT_ROOT"

# --- Check if destination already exists ---
if [ -e "$DEST" ]; then
  printf "Error: destination already exists: %s\n" "$DEST" >&2
  exit 1
fi

# --- Create worktree ---
if [ "$USE_BRANCH" = true ]; then
  printf "Error: --branch mode not yet implemented. Use worktrees instead.\n" >&2
  exit 1
fi

# Check if branch exists on origin
git fetch -- origin >/dev/null 2>&1 || true

if git ls-remote --exit-code --heads origin -- "$BRANCH_NAME" >/dev/null 2>&1; then
  printf "Branch exists on origin, creating tracking worktree...\n"
  # Ensure we have the remote tracking branch
  git fetch -- origin "refs/heads/$BRANCH_NAME:refs/remotes/origin/$BRANCH_NAME" 2>/dev/null || true
  git worktree add -b "$BRANCH_NAME" -- "$DEST" "origin/$BRANCH_NAME" || \
    git worktree add -- "$DEST" "$BRANCH_NAME"
else
  printf "Creating new branch from current HEAD...\n"
  git worktree add -b "$BRANCH_NAME" -- "$DEST"
  
  # Push to origin with tracking
  printf "Pushing branch to origin...\n"
  git -C "$DEST" push -u origin -- "$BRANCH_NAME"
fi

# --- Clean the worktree ---
printf "Cleaning worktree to minimal infrastructure...\n"

cd -- "$DEST"

# Keep only .git, .gitignore, and .devcontainer
KEEP_FILES=(
  ".git"
  ".gitignore"
)
KEEP_DIRS=(
  ".devcontainer"
)

# Remove all files except those we want to keep
for item in *; do
  [ ! -e "$item" ] && continue
  should_keep=false
  
  for keep in "${KEEP_FILES[@]}"; do
    if [ "$item" = "$keep" ]; then
      should_keep=true
      break
    fi
  done
  
  for keep in "${KEEP_DIRS[@]}"; do
    if [ "$item" = "$keep" ]; then
      should_keep=true
      break
    fi
  done
  
  if [ "$should_keep" = false ]; then
    printf '  Removing: %s\n' "$item"
    rm -rf -- "$item"
  fi
done

# Remove hidden files/dirs except .git, .gitignore, .devcontainer
for item in .[!.]*; do
  [ ! -e "$item" ] && continue
  case "$item" in
    .git|.gitignore|.devcontainer) continue ;;
    *) printf '  Removing: %s\n' "$item"; rm -rf -- "$item" ;;
  esac
done

# --- Setup devcontainer ---
printf "Setting up devcontainer...\n"

if [ -f ".devcontainer/prebuild/devcontainer.json" ]; then
  printf "  Moving prebuild devcontainer to main location...\n"
  
  PREBUILD_FILE=".devcontainer/prebuild/devcontainer.json"
  DEST_FILE=".devcontainer/devcontainer.json"
  
  # Remove the repositories section if it exists (using multiple approaches for portability)
  if command -v jq >/dev/null 2>&1; then
    # Use jq if available (reads directly from file)
    tmp_dest=$(mktemp "$DEST_FILE.XXXXXX")
    trap 'rm -f -- "$tmp_dest" 2>/dev/null || true' EXIT
    jq 'del(.customizations.codespaces.repositories)' -- "$PREBUILD_FILE" > "$tmp_dest" && mv -- "$tmp_dest" "$DEST_FILE"
    trap - EXIT
  elif command -v python3 >/dev/null 2>&1; then
    # Use Python if available (reads directly from file via env var)
    export PREBUILD_FILE DEST_FILE
    tmp_dest=$(mktemp "$DEST_FILE.XXXXXX")
    trap 'rm -f -- "$tmp_dest" 2>/dev/null || true' EXIT
    export tmp_dest
    python3 -c "
import json, sys, os
with open(os.environ['PREBUILD_FILE']) as f:
    data = json.load(f)
if 'customizations' in data and 'codespaces' in data['customizations']:
    if 'repositories' in data['customizations']['codespaces']:
        del data['customizations']['codespaces']['repositories']
with open(os.environ['tmp_dest'], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" && mv -- "$tmp_dest" "$DEST_FILE"
    trap - EXIT
  else
    # Fallback: just copy it (will have repositories section but still works)
    printf "  Warning: jq and python3 not found; copying devcontainer as-is\n"
    cp -- "$PREBUILD_FILE" "$DEST_FILE"
  fi
  
  # Remove prebuild directory
  rm -rf -- .devcontainer/prebuild
  printf "  ✓ Devcontainer configured\n"
elif [ -f ".devcontainer/devcontainer.json" ]; then
  printf "  Devcontainer already exists, keeping as-is\n"
else
  printf "  Warning: No devcontainer configuration found\n"
fi

# --- Commit the changes ---
printf "Committing infrastructure changes...\n"
git add -A --
git commit -m "Initialize ${BRANCH_NAME} branch with minimal infrastructure" -- || true
git push origin -- "$BRANCH_NAME" || true

# --- Update repos.list ---
cd -- "$PROJECT_ROOT"
printf "Adding branch to repos.list...\n"

# Check if @branch line already exists
if [ -f repos.list ] && awk -v branch="@${BRANCH_NAME}" -- '$1 == branch { found=1; exit 0 } END { if (found) exit 0; else exit 1 }' repos.list; then
  printf "  Branch already in repos.list\n"
else
  # Add after the current repo (first line or after any existing @branch lines from current repo)
  if [ -n "$TARGET_DIR" ]; then
    printf '@%s %s\n' "$BRANCH_NAME" "$TARGET_DIR" >> repos.list
  else
    printf '@%s\n' "$BRANCH_NAME" >> repos.list
  fi
  printf '  ✓ Added @%s to repos.list\n' "$BRANCH_NAME"
fi

# --- Update workspace ---
if [ -x "$SCRIPT_DIR/helper/vscode-workspace-add.sh" ]; then
  printf "Updating VS Code workspace...\n"
  "$SCRIPT_DIR/helper/vscode-workspace-add.sh" -f repos.list
  printf "  ✓ Workspace updated\n"
else
  printf "  Warning: vscode-workspace-add.sh not found; run it manually to update workspace\n"
fi

printf "\n"
printf "✅ Worktree created successfully!\n"
printf "   Location: %s\n" "$DEST"
printf "   Branch: %s\n" "$BRANCH_NAME"
printf "\n"
printf "Next steps:\n"
printf "  - Open in VS Code: code \"%s\"\n" "$DEST"
printf "  - Or open workspace: code \"%s/entire-project.code-workspace\"\n" "$PROJECT_ROOT"
printf "  - To remove: git worktree remove \"%s\"\n" "$DEST"
