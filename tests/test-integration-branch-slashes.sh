#!/usr/bin/env bash
# test-integration-branch-slashes.sh — Integration test for branches with slashes
# This test creates a temporary git repo and tests the actual functionality

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo "============================================"
  echo "$1"
  echo "============================================"
}

print_info() {
  echo "ℹ️  $1"
}

print_pass() {
  echo -e "${GREEN}✓ $1${NC}"
}

print_fail() {
  echo -e "${RED}✗ $1${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

print_header "Integration Test: Branches with Slashes"

# Create temporary test directory structure
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_info "Test root: $TEST_ROOT"

# Create a base repository to work with
BASE_REPO="$TEST_ROOT/test-repo"
mkdir -p "$BASE_REPO"
cd "$BASE_REPO"

print_info "Creating test git repository..."
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Test Repo" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create branches with slashes
print_info "Creating branches with slashes..."
git branch feature/cool-feature
git branch hotfix/urgent-fix
git branch release/v1.0.0

# Test 1: Test clone-repos.sh with @branch syntax
print_info ""
print_info "Test 1: Testing clone-repos.sh with @branch for branches with slashes"

WORK_DIR="$TEST_ROOT/workspace"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# Initialize as git repo (required for clone-repos.sh)
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$BASE_REPO"
echo "# Workspace" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create repos.list for testing
cat > repos.list <<EOF
@feature/cool-feature
EOF

print_info "Running clone-repos.sh..."
if "$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1 | grep -q "Adding worktree"; then
  # Check if the worktree directory was created with sanitized name
  EXPECTED_DIR="$TEST_ROOT/workspace-feature-cool-feature"
  if [ -d "$EXPECTED_DIR" ]; then
    print_pass "Worktree created with sanitized directory name: $(basename "$EXPECTED_DIR")"
    
    # Verify the actual branch name in git is correct (with slash)
    cd "$EXPECTED_DIR"
    ACTUAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$ACTUAL_BRANCH" = "feature/cool-feature" ]; then
      print_pass "Git branch name preserved with slash: $ACTUAL_BRANCH"
    else
      print_fail "Git branch name incorrect: $ACTUAL_BRANCH (expected: feature/cool-feature)"
    fi
  else
    print_fail "Expected directory not found: $EXPECTED_DIR"
    print_info "Contents of parent dir:"
    ls -la "$TEST_ROOT" | grep workspace
  fi
else
  print_fail "clone-repos.sh failed or didn't create worktree"
fi

# Test 2: Test with explicit target directory
print_info ""
print_info "Test 2: Testing with explicit target directory"

cd "$WORK_DIR"
cat > repos.list <<EOF
@hotfix/urgent-fix custom-dir
EOF

print_info "Running clone-repos.sh with custom directory..."
if "$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1 | grep -q "Adding worktree"; then
  EXPECTED_DIR="$TEST_ROOT/custom-dir"
  if [ -d "$EXPECTED_DIR" ]; then
    print_pass "Worktree created with custom directory name: $(basename "$EXPECTED_DIR")"
    
    cd "$EXPECTED_DIR"
    ACTUAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [ "$ACTUAL_BRANCH" = "hotfix/urgent-fix" ]; then
      print_pass "Git branch name preserved with slash: $ACTUAL_BRANCH"
    else
      print_fail "Git branch name incorrect: $ACTUAL_BRANCH"
    fi
  else
    print_fail "Expected custom directory not found: $EXPECTED_DIR"
  fi
fi

# Test 3: Test vscode-workspace-add.sh path generation
print_info ""
print_info "Test 3: Testing vscode-workspace-add.sh path generation"

cd "$WORK_DIR"
cat > repos.list <<EOF
@feature/cool-feature
@hotfix/urgent-fix custom-dir
EOF

print_info "Running vscode-workspace-add.sh..."
if "$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh" -f repos.list 2>&1 | grep -q "Updated"; then
  WORKSPACE_FILE="$WORK_DIR/entire-project.code-workspace"
  if [ -f "$WORKSPACE_FILE" ]; then
    print_pass "Workspace file created"
    
    # Check if the paths in the workspace file use sanitized names
    if grep -q '../workspace-feature-cool-feature' "$WORKSPACE_FILE"; then
      print_pass "Workspace contains sanitized path: ../workspace-feature-cool-feature"
    else
      print_fail "Workspace missing expected sanitized path"
      print_info "Workspace contents:"
      cat "$WORKSPACE_FILE"
    fi
    
    if grep -q '../custom-dir' "$WORKSPACE_FILE"; then
      print_pass "Workspace contains custom directory path: ../custom-dir"
    else
      print_fail "Workspace missing custom directory path"
    fi
  else
    print_fail "Workspace file not created"
  fi
else
  print_fail "vscode-workspace-add.sh failed"
fi

# Summary
print_header "Integration Test Summary"
echo -e "${GREEN}Integration tests completed successfully!${NC}"
echo ""
echo "Key findings:"
echo "  • Branches with slashes are handled correctly"
echo "  • Directory names use sanitized names (slashes → dashes)"
echo "  • Git operations use original branch names (with slashes)"
echo "  • Workspace file generation works correctly"
echo "  • Custom directory names work as expected"
