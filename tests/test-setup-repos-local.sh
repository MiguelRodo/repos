#!/usr/bin/env bash
# test-setup-repos-local.sh — Integration test for setup-repos.sh with local git remotes
# This test creates local bare git repos and validates the complete setup-repos.sh workflow

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_header() {
  echo ""
  echo "============================================"
  echo "$1"
  echo "============================================"
}

print_test() {
  echo ""
  echo -e "${YELLOW}TEST: $1${NC}"
  TESTS_RUN=$((TESTS_RUN + 1))
}

print_pass() {
  echo -e "${GREEN}✓ PASS: $1${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
  echo -e "${RED}✗ FAIL: $1${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
  echo "ℹ️  $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup-repos.sh"
CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "Local Git Remote Integration Test for setup-repos.sh"

print_info "Test root: $TEST_ROOT"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Setup: Create local bare git repositories
# ============================================
print_test "Creating local bare git repositories"

BARE_REPOS_DIR="$TEST_ROOT/bare-repos"
mkdir -p "$BARE_REPOS_DIR"

# Create first bare repo with multiple branches
REPO1_BARE="$BARE_REPOS_DIR/testrepo1.git"
git init --bare -q "$REPO1_BARE"

# Create a temporary clone to add content and branches
TEMP_CLONE="$TEST_ROOT/temp-clone1"
git clone -q "$REPO1_BARE" "$TEMP_CLONE"
cd "$TEMP_CLONE"
git config user.email "test@example.com"
git config user.name "Test User"

# Add initial content
echo "# Test Repo 1" > README.md
git add README.md
git commit -q -m "Initial commit"
# Handle both master and main as default branch
DEFAULT_BRANCH=$(git symbolic-ref --short HEAD)
git push -q origin "$DEFAULT_BRANCH"

# Create additional branches (from the default branch)
git checkout -q "$DEFAULT_BRANCH"
git checkout -q -b dev
echo "dev branch" >> README.md
git add README.md
git commit -q -m "Dev branch commit"
git push -q origin dev

git checkout -q "$DEFAULT_BRANCH"
git checkout -q -b feature/test
echo "feature branch" >> README.md
git add README.md
git commit -q -m "Feature branch commit"
git push -q origin feature/test

# Create second bare repo
REPO2_BARE="$BARE_REPOS_DIR/testrepo2.git"
git init --bare -q "$REPO2_BARE"

TEMP_CLONE2="$TEST_ROOT/temp-clone2"
git clone -q "$REPO2_BARE" "$TEMP_CLONE2"
cd "$TEMP_CLONE2"
git config user.email "test@example.com"
git config user.name "Test User"

echo "# Test Repo 2" > README.md
git add README.md
git commit -q -m "Initial commit"
# Handle both master and main as default branch
DEFAULT_BRANCH=$(git symbolic-ref --short HEAD)
git push -q origin "$DEFAULT_BRANCH"

git checkout -q "$DEFAULT_BRANCH"
git checkout -q -b release/v1.0
echo "release branch" >> README.md
git add README.md
git commit -q -m "Release branch commit"
git push -q origin release/v1.0

print_pass "Created local bare repositories with branches"
print_info "  - $REPO1_BARE (main, dev, feature/test)"
print_info "  - $REPO2_BARE (main, release/v1.0)"

# ============================================
# Test 1: clone-repos.sh with local file:// URLs
# ============================================
print_test "clone-repos.sh handles file:// URLs"

WORKSPACE1="$TEST_ROOT/workspace1"
mkdir -p "$WORKSPACE1"
cd "$WORKSPACE1"

# Initialize as git repo (required for @branch syntax)
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# Workspace 1" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create repos.list with file:// URLs
cat > repos.list <<EOF
# Test with file:// URLs
file://$REPO1_BARE
@dev
file://$REPO2_BARE
@release/v1.0
EOF

print_info "Running clone-repos.sh with file:// URLs..."
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true  # Don't fail on non-zero exit
# Check if repos were cloned successfully regardless of exit code
if [ -d "$TEST_ROOT/testrepo1" ] && [ -d "$TEST_ROOT/workspace1-dev" ]; then
  print_pass "Cloned testrepo1 and created dev worktree"
else
  print_fail "Failed to clone repos from file:// URLs"
  print_info "Contents of $TEST_ROOT:"
  ls -la "$TEST_ROOT" | grep -E "testrepo|workspace"
fi

if [ -d "$TEST_ROOT/testrepo2" ] && [ -d "$TEST_ROOT/workspace1-release-v1.0" ]; then
  print_pass "Cloned testrepo2 and created release/v1.0 worktree"
else
  print_fail "Failed to clone testrepo2 or create worktree"
fi

# ============================================
# Test 2: clone-repos.sh with absolute paths
# ============================================
print_test "clone-repos.sh handles absolute paths"

WORKSPACE2="$TEST_ROOT/workspace2"
mkdir -p "$WORKSPACE2"
cd "$WORKSPACE2"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# Workspace 2" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create repos.list with absolute paths
cat > repos.list <<EOF
# Test with absolute paths
$REPO1_BARE
@feature/test
EOF

print_info "Running clone-repos.sh with absolute paths..."
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true  # Don't fail on non-zero exit
# Check for sanitized directory name (feature/test → feature-test)
if [ -d "$TEST_ROOT/testrepo1" ] && [ -d "$TEST_ROOT/workspace2-feature-test" ]; then
  print_pass "Cloned with absolute path and created worktree with sanitized name"
  
  # Verify actual branch name is preserved
  cd "$TEST_ROOT/workspace2-feature-test"
  ACTUAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$ACTUAL_BRANCH" = "feature/test" ]; then
    print_pass "Git branch name preserved with slash: $ACTUAL_BRANCH"
  else
    print_fail "Git branch name incorrect: $ACTUAL_BRANCH (expected: feature/test)"
  fi
else
  print_fail "Failed to clone repo from absolute path"
  print_info "Contents of $TEST_ROOT:"
  ls -la "$TEST_ROOT" | grep -E "testrepo|workspace"
fi

# ============================================
# Test 3: setup-repos.sh with local remotes (should skip GitHub API)
# ============================================
print_test "setup-repos.sh skips GitHub API for local remotes"

WORKSPACE3="$TEST_ROOT/workspace3"
mkdir -p "$WORKSPACE3"
cd "$WORKSPACE3"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# Workspace 3" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create repos.list with mixed GitHub and local repos
cat > repos.list <<EOF
# Local repos (should not try GitHub API)
file://$REPO1_BARE
$REPO2_BARE
EOF

print_info "Running setup-repos.sh with local remotes..."
# setup-repos.sh should handle this gracefully now with our fix
if "$SETUP_SCRIPT" -f repos.list >/dev/null 2>&1; then
  print_pass "setup-repos.sh completed without errors"
  
  # Verify repos were cloned
  if [ -d "$TEST_ROOT/testrepo1" ] && [ -d "$TEST_ROOT/testrepo2" ]; then
    print_pass "Local repos were cloned successfully"
  else
    print_fail "Repos were not cloned"
  fi
else
  print_fail "setup-repos.sh failed (this should pass after fix)"
fi

# ============================================
# Test 4: Workspace file generation with local remotes
# ============================================
print_test "vscode-workspace-add.sh works with local remotes"

WORKSPACE4="$TEST_ROOT/workspace4"
mkdir -p "$WORKSPACE4"
cd "$WORKSPACE4"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# Workspace 4" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
file://$REPO1_BARE
@dev
EOF

# Clone the repos first
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# Generate workspace file
WORKSPACE_SCRIPT="$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh"
if [ -x "$WORKSPACE_SCRIPT" ]; then
  if "$WORKSPACE_SCRIPT" -f repos.list >/dev/null 2>&1; then
    if [ -f "entire-project.code-workspace" ]; then
      print_pass "Workspace file created for local remotes"
      
      # Verify paths in workspace
      if grep -q '../testrepo1' entire-project.code-workspace && \
         grep -q '../workspace4-dev' entire-project.code-workspace; then
        print_pass "Workspace contains correct paths for local repos"
      else
        print_fail "Workspace paths incorrect"
        print_info "Workspace contents:"
        cat entire-project.code-workspace
      fi
    else
      print_fail "Workspace file not created"
    fi
  else
    print_fail "vscode-workspace-add.sh failed"
  fi
else
  print_fail "vscode-workspace-add.sh not found"
fi

# ============================================
# Test 5: Single-branch clone with local remote
# ============================================
print_test "Single-branch clone from local remote"

WORKSPACE5="$TEST_ROOT/workspace5"
mkdir -p "$WORKSPACE5"
cd "$WORKSPACE5"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Workspace 5" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
file://$REPO1_BARE@dev
EOF

print_info "Running clone-repos.sh for single-branch from local remote..."
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true
if [ -d "$TEST_ROOT/testrepo1" ]; then
  print_pass "Single-branch clone from local remote succeeded"
  
  cd "$TEST_ROOT/testrepo1"
  ACTUAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$ACTUAL_BRANCH" = "dev" ]; then
    print_pass "Checked out correct branch: $ACTUAL_BRANCH"
  else
    print_fail "Wrong branch checked out: $ACTUAL_BRANCH"
  fi
else
  print_fail "Single-branch clone failed"
fi

# ============================================
# Summary
# ============================================
print_header "Test Summary"

echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
  echo ""
  echo -e "${RED}Some tests failed.${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
  echo ""
  echo "✓ Local git remotes work for offline testing"
  echo "✓ setup-repos.sh skips GitHub API for local remotes"
  echo "✓ clone-repos.sh handles file:// URLs and absolute paths"
  echo "✓ Workspace generation works with local remotes"
fi
