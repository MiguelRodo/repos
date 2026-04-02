#!/usr/bin/env bash
# test-setup-repos-local.sh — Integration test for setup-repos.sh with local git remotes
# This test creates local bare git repos and validates the complete setup-repos.sh workflow

set -e

# Colors for output
NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_header() {
  echo -e "\n============================================"
  echo "$1"
  echo "============================================"
}

print_test() {
  echo -e "\n${YELLOW}TEST: $1${NC}"
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
WORKSPACE_SCRIPT="$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh"

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "Local Git Remote Integration Test for setup-repos.sh"
print_info "Test root: $TEST_ROOT"

# ============================================
# Setup: Create local bare git repositories
# ============================================
print_test "Creating local bare git repositories"

BARE_REPOS_DIR="$TEST_ROOT/bare-repos"
mkdir -p "$BARE_REPOS_DIR"

# Create first bare repo
REPO1_BARE="$BARE_REPOS_DIR/testrepo1.git"
git init --bare -q "$REPO1_BARE"
TEMP_CLONE1="$TEST_ROOT/temp-clone1"
git clone -q "$REPO1_BARE" "$TEMP_CLONE1"
(
  cd "$TEMP_CLONE1"
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo "# Test Repo 1" > README.md
  git add README.md
  git commit -q -m "Initial commit"
  DEFAULT_BRANCH=$(git symbolic-ref --short HEAD)
  git push -q origin "$DEFAULT_BRANCH"
  git checkout -q -b dev
  git push -q origin dev
  git checkout -q "$DEFAULT_BRANCH"
  git checkout -q -b feature/test
  git push -q origin feature/test
)

# Create second bare repo
REPO2_BARE="$BARE_REPOS_DIR/testrepo2.git"
git init --bare -q "$REPO2_BARE"
TEMP_CLONE2="$TEST_ROOT/temp-clone2"
git clone -q "$REPO2_BARE" "$TEMP_CLONE2"
(
  cd "$TEMP_CLONE2"
  git config user.email "test@example.com"
  git config user.name "Test User"
  echo "# Test Repo 2" > README.md
  git add README.md
  git commit -q -m "Initial commit"
  DEFAULT_BRANCH=$(git symbolic-ref --short HEAD)
  git push -q origin "$DEFAULT_BRANCH"
  git checkout -q -b release/v1.0
  git push -q origin release/v1.0
)

print_pass "Created local bare repositories with branches"

# ============================================
# Test 1: clone-repos.sh with local file:// URLs
# ============================================
print_test "clone-repos.sh handles file:// URLs"

WORKSPACE1="$TEST_ROOT/workspace1"
mkdir -p "$WORKSPACE1"
(
  cd "$WORKSPACE1"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  git remote add origin "$REPO1_BARE"
  echo "# Workspace 1" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  cat > repos.list <<EOF
file://$REPO1_BARE testrepo1-file
@dev workspace1-dev
EOF

  "$CLONE_SCRIPT" -f repos.list
)

if [ -d "$TEST_ROOT/testrepo1-file" ] && [ -d "$TEST_ROOT/workspace1-dev" ]; then
  print_pass "Cloned from file:// URLs correctly"
else
  print_fail "Failed to clone from file:// URLs"
  ls -la "$TEST_ROOT"
fi

# ============================================
# Test 2: clone-repos.sh with absolute paths
# ============================================
print_test "clone-repos.sh handles absolute paths"

WORKSPACE2="$TEST_ROOT/workspace2"
mkdir -p "$WORKSPACE2"
(
  cd "$WORKSPACE2"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  git remote add origin "$REPO1_BARE"
  echo "# Workspace 2" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  cat > repos.list <<EOF
$REPO1_BARE testrepo1-abs
@feature/test workspace2-feature-test
EOF

  "$CLONE_SCRIPT" -f repos.list
)

if [ -d "$TEST_ROOT/testrepo1-abs" ] && [ -d "$TEST_ROOT/workspace2-feature-test" ]; then
  print_pass "Cloned from absolute paths correctly"
  (
    cd "$TEST_ROOT/workspace2-feature-test"
    ACTUAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [ "$ACTUAL_BRANCH" = "feature/test" ]; then
      print_pass "Branch feature/test preserved"
    else
      print_fail "Branch mismatch: $ACTUAL_BRANCH"
    fi
  )
else
  print_fail "Failed to clone from absolute paths"
  ls -la "$TEST_ROOT"
fi

# ============================================
# Test 3: setup-repos.sh with local remotes
# ============================================
print_test "setup-repos.sh works with local remotes"

WORKSPACE3="$TEST_ROOT/workspace3"
mkdir -p "$WORKSPACE3"
(
  cd "$WORKSPACE3"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  git remote add origin "$REPO1_BARE"
  echo "# Workspace 3" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  cat > repos.list <<EOF
file://$REPO1_BARE testrepo1-setup
$REPO2_BARE testrepo2-setup
EOF

  "$SETUP_SCRIPT" -f repos.list
)

if [ -d "$TEST_ROOT/testrepo1-setup" ] && [ -d "$TEST_ROOT/testrepo2-setup" ]; then
  print_pass "setup-repos.sh cloned local repos"
else
  print_fail "setup-repos.sh failed to clone local repos"
fi

# ============================================
# Test 4: vscode-workspace-add.sh works with local remotes
# ============================================
print_test "vscode-workspace-add.sh works with local remotes"

WORKSPACE4="$TEST_ROOT/workspace4"
mkdir -p "$WORKSPACE4"
(
  cd "$WORKSPACE4"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  git remote add origin "$REPO1_BARE"
  echo "# Workspace 4" > README.md
  git add README.md
  git commit -q -m "Initial commit"

  cat > repos.list <<EOF
file://$REPO1_BARE testrepo1-ws
@dev workspace4-dev
EOF

  "$CLONE_SCRIPT" -f repos.list
  "$WORKSPACE_SCRIPT" -f repos.list
)

if [ -f "$WORKSPACE4/entire-project.code-workspace" ]; then
  if grep -q '../testrepo1-ws' "$WORKSPACE4/entire-project.code-workspace" && \
     grep -q '../workspace4-dev' "$WORKSPACE4/entire-project.code-workspace"; then
    print_pass "Workspace contains correct relative paths"
  else
    print_fail "Workspace paths incorrect"
    cat "$WORKSPACE4/entire-project.code-workspace"
  fi
else
  print_fail "Workspace file not created"
fi

# ============================================
# Summary
# ============================================
print_header "Test Summary"
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"

if [ "$TESTS_FAILED" -gt 0 ]; then
  exit 1
fi
