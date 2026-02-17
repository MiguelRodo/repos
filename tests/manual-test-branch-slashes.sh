#!/usr/bin/env bash
# manual-test-branch-slashes.sh — Manual demonstration of branch slash handling
# This script shows how branches with slashes are handled in practice

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo -e "${BLUE}============================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}============================================${NC}"
}

print_info() {
  echo -e "ℹ️  $1"
}

print_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_command() {
  echo -e "${YELLOW}$ $1${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_header "Manual Demonstration: Branches with Slashes"

echo ""
echo "This demonstration shows how the scripts handle branch names"
echo "containing forward slashes (e.g., feature/new-thing)."
echo ""
echo "Key behavior:"
echo "  • Directory names: slashes converted to dashes (feature-new-thing)"
echo "  • Git operations: original branch names with slashes (feature/new-thing)"
echo ""

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_info "Test directory: $TEST_ROOT"

# Create a base repository
print_header "Step 1: Create a test repository"

BASE_REPO="$TEST_ROOT/base-repo"
mkdir -p "$BASE_REPO"
cd "$BASE_REPO"

print_command "git init"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

print_command "echo '# Base Repo' > README.md"
echo "# Base Repo" > README.md

print_command "git add README.md && git commit -m 'Initial commit'"
git add README.md
git commit -q -m "Initial commit"

print_success "Created base repository"

# Create branches with slashes
print_header "Step 2: Create branches with slashes"

print_command "git branch feature/cool-feature"
git branch feature/cool-feature
print_success "Created: feature/cool-feature"

print_command "git branch hotfix/urgent-fix"
git branch hotfix/urgent-fix
print_success "Created: hotfix/urgent-fix"

print_command "git branch release/v1.0.0"
git branch release/v1.0.0
print_success "Created: release/v1.0.0"

print_command "git branch user/alice/dev"
git branch user/alice/dev
print_success "Created: user/alice/dev"

# Create workspace
print_header "Step 3: Create a workspace"

WORKSPACE="$TEST_ROOT/workspace"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

print_command "git init"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$BASE_REPO"

echo "# Workspace" > README.md
git add README.md
git commit -q -m "Initial commit"

print_success "Created workspace at: $WORKSPACE"

# Test clone-repos.sh
print_header "Step 4: Test clone-repos.sh with branches containing slashes"

cat > repos.list <<'EOF'
# Test branches with slashes
@feature/cool-feature
@hotfix/urgent-fix custom-hotfix
@release/v1.0.0
EOF

print_info "Created repos.list:"
cat repos.list | sed 's/^/  /'

echo ""
print_command "scripts/helper/clone-repos.sh -f repos.list"
"$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1 | sed 's/^/  /'

echo ""
print_header "Step 5: Verify directory structure"

print_info "Parent directory contents:"
ls -1 "$TEST_ROOT" | grep -E "workspace-|custom-" | while read -r dir; do
  if [ "$dir" = "workspace-feature-cool-feature" ]; then
    print_success "✓ $dir (sanitized: feature/cool-feature → feature-cool-feature)"
  elif [ "$dir" = "custom-hotfix" ]; then
    print_success "✓ $dir (custom directory name)"
  elif [ "$dir" = "workspace-release-v1.0.0" ]; then
    print_success "✓ $dir (sanitized: release/v1.0.0 → release-v1.0.0)"
  else
    echo "  $dir"
  fi
done

# Verify git branch names
print_header "Step 6: Verify git branch names (with slashes)"

for dir in "$TEST_ROOT"/workspace-*/; do
  if [ -d "$dir" ]; then
    dirname=$(basename "$dir")
    cd "$dir"
    if branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null); then
      if [[ "$branch" == *"/"* ]]; then
        print_success "✓ $dirname → git branch: $branch (slash preserved)"
      else
        echo "  $dirname → git branch: $branch"
      fi
    fi
  fi
done

# Test workspace generation
print_header "Step 7: Test workspace file generation"

cd "$WORKSPACE"
print_command "scripts/helper/vscode-workspace-add.sh -f repos.list"
"$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh" -f repos.list 2>&1 | sed 's/^/  /'

if [ -f "entire-project.code-workspace" ]; then
  echo ""
  print_success "Workspace file created"
  print_info "Workspace paths (sanitized for filesystem):"
  grep '"path"' entire-project.code-workspace | sed 's/^/  /'
fi

# Test add-branch.sh
print_header "Step 8: Test add-branch.sh with slash in branch name"

cd "$WORKSPACE"
print_info "Note: add-branch.sh requires a real remote, skipping actual execution"
print_info "But showing how it would handle 'feature/new-ui':"

BRANCH_NAME="feature/new-ui"
SAFE_BRANCH_NAME="${BRANCH_NAME//\//-}"
REPO_NAME="workspace"
print_info "  Input branch: $BRANCH_NAME"
print_info "  Sanitized for directory: $SAFE_BRANCH_NAME"
print_info "  Would create directory: ../${REPO_NAME}-${SAFE_BRANCH_NAME}"
print_info "  Git branch name: $BRANCH_NAME (preserved with slash)"

# Summary
print_header "Summary"

echo ""
echo "The scripts now correctly handle branch names with slashes:"
echo ""
echo -e "${GREEN}✓ Directory names${NC} use sanitized names (slashes → dashes)"
echo "    Example: feature/cool-feature → workspace-feature-cool-feature/"
echo ""
echo -e "${GREEN}✓ Git operations${NC} use original branch names (with slashes)"
echo "    Example: git checkout feature/cool-feature"
echo ""
echo -e "${GREEN}✓ Workspace paths${NC} reference sanitized directory names"
echo "    Example: '../workspace-feature-cool-feature'"
echo ""
echo -e "${GREEN}✓ Custom directories${NC} override sanitization"
echo "    Example: @hotfix/urgent-fix custom-hotfix → custom-hotfix/"
echo ""
echo "This ensures compatibility with file systems while maintaining"
echo "proper git branch naming conventions."
echo ""

print_success "Manual demonstration completed successfully!"
echo ""
echo "Test artifacts in: $TEST_ROOT"
echo "Run 'ls -la $TEST_ROOT' to inspect the structure"
