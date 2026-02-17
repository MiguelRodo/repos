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

set -Eeo pipefail

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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
    -*)
      echo "Error: Unknown option: $1" >&2
      usage; exit 1 ;;
    *)
      if [ -z "$BRANCH_NAME" ]; then
        BRANCH_NAME="$1"
      elif [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$1"
      else
        echo "Error: Too many arguments" >&2
        usage; exit 1
      fi
      shift ;;
  esac
done

if [ -z "$BRANCH_NAME" ]; then
  echo "Error: branch-name is required" >&2
  usage
  exit 1
fi

# --- Validate we're in a git repo ---
cd "$PROJECT_ROOT"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: not inside a Git working tree" >&2
  exit 1
fi

# Sanitize branch name for use in directory paths
# Replaces forward slashes with dashes to avoid nested directories
sanitize_branch_name() {
  local branch="$1"
  printf '%s\n' "${branch//\//-}"
}

# --- Determine destination ---
REPO_NAME="$(basename "$PROJECT_ROOT")"
PARENT_DIR="$(dirname "$PROJECT_ROOT")"

if [ -n "$TARGET_DIR" ]; then
  DEST="$PARENT_DIR/$TARGET_DIR"
else
  SAFE_BRANCH_NAME="$(sanitize_branch_name "$BRANCH_NAME")"
  DEST="$PARENT_DIR/${REPO_NAME}-${SAFE_BRANCH_NAME}"
fi

echo "Creating worktree: $DEST"
echo "  Branch: $BRANCH_NAME"
echo "  Base repo: $PROJECT_ROOT"

# --- Check if destination already exists ---
if [ -e "$DEST" ]; then
  echo "Error: destination already exists: $DEST" >&2
  exit 1
fi

# --- Create worktree ---
if [ "$USE_BRANCH" = true ]; then
  echo "Error: --branch mode not yet implemented. Use worktrees instead." >&2
  exit 1
fi

# Check if branch exists on origin
git fetch origin >/dev/null 2>&1 || true

if git ls-remote --exit-code --heads origin "$BRANCH_NAME" >/dev/null 2>&1; then
  echo "Branch exists on origin, creating tracking worktree..."
  # Ensure we have the remote tracking branch
  git fetch origin "refs/heads/$BRANCH_NAME:refs/remotes/origin/$BRANCH_NAME" 2>/dev/null || true
  git worktree add -b "$BRANCH_NAME" "$DEST" "origin/$BRANCH_NAME" || \
    git worktree add "$DEST" "$BRANCH_NAME"
else
  echo "Creating new branch from current HEAD..."
  git worktree add -b "$BRANCH_NAME" "$DEST"
  
  # Push to origin with tracking
  echo "Pushing branch to origin..."
  git -C "$DEST" push -u origin "$BRANCH_NAME"
fi

# --- Clean the worktree ---
echo "Cleaning worktree to minimal infrastructure..."

cd "$DEST"

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
    echo "  Removing: $item"
    rm -rf "$item"
  fi
done

# Remove hidden files/dirs except .git, .gitignore, .devcontainer
for item in .[!.]*; do
  [ ! -e "$item" ] && continue
  case "$item" in
    .git|.gitignore|.devcontainer) continue ;;
    *) echo "  Removing: $item"; rm -rf "$item" ;;
  esac
done

# --- Setup devcontainer ---
echo "Setting up devcontainer..."

if [ -f ".devcontainer/prebuild/devcontainer.json" ]; then
  echo "  Moving prebuild devcontainer to main location..."
  
  # Read the prebuild devcontainer
  PREBUILD_CONTENT="$(cat .devcontainer/prebuild/devcontainer.json)"
  
  # Remove the repositories section if it exists (using multiple approaches for portability)
  if command -v jq >/dev/null 2>&1; then
    # Use jq if available
    echo "$PREBUILD_CONTENT" | jq 'del(.customizations.codespaces.repositories)' > .devcontainer/devcontainer.json
  elif command -v python3 >/dev/null 2>&1; then
    # Use Python if available
    python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
if 'customizations' in data and 'codespaces' in data['customizations']:
    if 'repositories' in data['customizations']['codespaces']:
        del data['customizations']['codespaces']['repositories']
print(json.dumps(data, indent=2))
" <<< "$PREBUILD_CONTENT" > .devcontainer/devcontainer.json
  else
    # Fallback: just copy it (will have repositories section but still works)
    echo "  Warning: jq and python3 not found; copying devcontainer as-is"
    cp .devcontainer/prebuild/devcontainer.json .devcontainer/devcontainer.json
  fi
  
  # Remove prebuild directory
  rm -rf .devcontainer/prebuild
  echo "  ✓ Devcontainer configured"
elif [ -f ".devcontainer/devcontainer.json" ]; then
  echo "  Devcontainer already exists, keeping as-is"
else
  echo "  Warning: No devcontainer configuration found"
fi

# --- Commit the changes ---
echo "Committing infrastructure changes..."
git add -A
git commit -m "Initialize ${BRANCH_NAME} branch with minimal infrastructure" || true
git push origin "$BRANCH_NAME" || true

# --- Update repos.list ---
cd "$PROJECT_ROOT"
echo "Adding branch to repos.list..."

# Check if @branch line already exists
if grep -q "^@${BRANCH_NAME}" repos.list 2>/dev/null; then
  echo "  Branch already in repos.list"
else
  # Add after the current repo (first line or after any existing @branch lines from current repo)
  if [ -n "$TARGET_DIR" ]; then
    echo "@${BRANCH_NAME} ${TARGET_DIR}" >> repos.list
  else
    echo "@${BRANCH_NAME}" >> repos.list
  fi
  echo "  ✓ Added @${BRANCH_NAME} to repos.list"
fi

# --- Update workspace ---
if [ -x "$SCRIPT_DIR/helper/vscode-workspace-add.sh" ]; then
  echo "Updating VS Code workspace..."
  "$SCRIPT_DIR/helper/vscode-workspace-add.sh" -f repos.list
  echo "  ✓ Workspace updated"
else
  echo "  Warning: vscode-workspace-add.sh not found; run it manually to update workspace"
fi

echo ""
echo "✅ Worktree created successfully!"
echo "   Location: $DEST"
echo "   Branch: $BRANCH_NAME"
echo ""
echo "Next steps:"
echo "  - Open in VS Code: code \"$DEST\""
echo "  - Or open workspace: code \"$PROJECT_ROOT/entire-project.code-workspace\""
echo "  - To remove: git worktree remove \"$DEST\""
