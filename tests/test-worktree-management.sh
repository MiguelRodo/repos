#!/usr/bin/env bash
# test-worktree-management.sh — Test suite for add-branch.sh and update-branches.sh

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
ADD_BRANCH_SCRIPT="$PROJECT_ROOT/scripts/add-branch.sh"
UPDATE_BRANCHES_SCRIPT="$PROJECT_ROOT/scripts/update-branches.sh"
WORKSPACE_SCRIPT="$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh"

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "Worktree Management Test Suite"

print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# Setup test environment
setup_test_env() {
  cd "$TEST_DIR"
  mkdir -p test-project/.devcontainer/prebuild
  mkdir -p test-project/scripts/helper

  # Create devcontainer
  cat > test-project/.devcontainer/prebuild/devcontainer.json <<'EOF'
{
  "name": "Test Devcontainer",
  "customizations": {
    "codespaces": {
      "repositories": {
        "owner/repo": {
          "permissions": "write-all"
        }
      }
    }
  }
}
EOF

  # Copy scripts
  cp -r "$PROJECT_ROOT/scripts" test-project/
  chmod +x test-project/scripts/*.sh
  chmod +x test-project/scripts/helper/*.sh

  # Initialize git repo
  cd test-project
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial commit
  echo "Initial content" > README.md
  git add .
  git commit -q -m "Initial commit"

  # Create dummy remote
  mkdir -p ../remote.git
  git init --bare -q ../remote.git
  git remote add origin "file://$(cd ../remote.git && pwd)"
  git push -q -u origin master

  # Create repos.list
  touch repos.list
  git add repos.list
  git commit -q -m "Add repos.list"
  git push -q origin master
}

setup_test_env

# ============================================
# Test 1: add-branch.sh basic functionality
# ============================================
print_test "add-branch.sh creates worktree and updates configuration"

cd "$TEST_DIR/test-project"

# Run add-branch.sh
./scripts/add-branch.sh test-feature

# Verify worktree created
if [ -d "../test-project-test-feature" ]; then
  print_pass "Worktree directory created"
else
  print_fail "Worktree directory not created"
fi

# Verify worktree is registered
if git worktree list | grep -q "test-project-test-feature"; then
  print_pass "Worktree registered in git"
else
  print_fail "Worktree not registered in git"
fi

# Verify devcontainer.json moved and stripped
WT_DIR="../test-project-test-feature"
if [ -f "$WT_DIR/.devcontainer/devcontainer.json" ]; then
  if ! grep -q "repositories" "$WT_DIR/.devcontainer/devcontainer.json"; then
    print_pass "devcontainer.json created and stripped of repositories"
  else
    print_fail "devcontainer.json contains repositories section (should be stripped)"
  fi
else
  print_fail "devcontainer.json not found in worktree"
fi

# Verify clean worktree (no prebuild dir)
if [ ! -d "$WT_DIR/.devcontainer/prebuild" ]; then
  print_pass "prebuild directory removed from worktree"
else
  print_fail "prebuild directory still exists in worktree"
fi

# Verify repos.list updated
if grep -q "@test-feature" repos.list; then
  print_pass "repos.list updated with @test-feature"
else
  print_fail "repos.list not updated"
fi

# Verify workspace updated
if [ -f "entire-project.code-workspace" ]; then
  if grep -q "test-project-test-feature" "entire-project.code-workspace"; then
    print_pass "Workspace file updated with new worktree"
  else
    print_fail "Workspace file does not contain new worktree"
  fi
else
  print_fail "Workspace file not created"
fi

# ============================================
# Test 2: add-branch.sh with custom directory
# ============================================
print_test "add-branch.sh with custom directory"

cd "$TEST_DIR/test-project"

# Run add-branch.sh with custom dir
./scripts/add-branch.sh test-custom custom-worktree

# Verify worktree created
if [ -d "../custom-worktree" ]; then
  print_pass "Custom worktree directory created"
else
  print_fail "Custom worktree directory not created"
fi

# Verify repos.list updated
if grep -q "@test-custom custom-worktree" repos.list; then
  print_pass "repos.list updated with custom directory"
else
  print_fail "repos.list not updated correctly for custom dir"
fi

# ============================================
# Test 3: update-branches.sh functionality
# ============================================
print_test "update-branches.sh updates devcontainers in worktrees"

cd "$TEST_DIR/test-project"

# Modify prebuild devcontainer
# Use temporary file for portable sed editing
sed 's/"Test Devcontainer"/"Updated Devcontainer"/' .devcontainer/prebuild/devcontainer.json > .devcontainer/prebuild/devcontainer.json.tmp
mv .devcontainer/prebuild/devcontainer.json.tmp .devcontainer/prebuild/devcontainer.json

# Run update-branches.sh
# We need to ensure we capture the output to verify it processed the worktrees
output=$(./scripts/update-branches.sh 2>&1)

# Check output for confirmation
if echo "$output" | grep -q "Updated devcontainer.json"; then
  print_pass "Script reported updates"
else
  print_fail "Script did not report updates"
  print_info "Output: $output"
fi

# Verify worktree updated
WT_DIR="../test-project-test-feature"
if grep -q "Updated Devcontainer" "$WT_DIR/.devcontainer/devcontainer.json"; then
  print_pass "Worktree devcontainer updated with new content"
else
  print_fail "Worktree devcontainer not updated"
fi

# Verify custom worktree updated
CUSTOM_WT_DIR="../custom-worktree"
if grep -q "Updated Devcontainer" "$CUSTOM_WT_DIR/.devcontainer/devcontainer.json"; then
  print_pass "Custom worktree devcontainer updated"
else
  print_fail "Custom worktree devcontainer not updated"
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
fi
