#!/usr/bin/env bash
# test-vscode-workspace.sh — Test suite for vscode-workspace-add.sh

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
WORKSPACE_SCRIPT="$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh"

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "VS Code Workspace Generation Test Suite"

print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test 1: Basic workspace generation
# ============================================
print_test "Generate workspace from simple repos.list"

cd "$TEST_DIR"
mkdir -p basic-test
cd basic-test

cat > repos.list <<'EOF'
owner/repo1
owner/repo2
EOF

"$WORKSPACE_SCRIPT" -f repos.list >/dev/null

if [ -f "entire-project.code-workspace" ]; then
  print_pass "Workspace file created"
else
  print_fail "Workspace file not created"
fi

# Validate content with jq if available
if command -v jq >/dev/null 2>&1; then
  paths=$(jq -r '.folders[].path' entire-project.code-workspace | sort)
  expected=$(printf ".\n../repo1\n../repo2" | sort)

  if [ "$paths" = "$expected" ]; then
    print_pass "Workspace contains correct paths"
  else
    print_fail "Workspace paths incorrect"
    print_info "Expected:\n$expected"
    print_info "Got:\n$paths"
  fi
else
  print_info "Skipping content validation (jq not found)"
fi

# ============================================
# Test 2: Custom directories and worktrees
# ============================================
print_test "Handle custom directories and worktrees"

cd "$TEST_DIR"
mkdir -p complex-test
cd complex-test

cat > repos.list <<'EOF'
# Standard clone
owner/repo1

# Worktree off repo1
@feature --worktree

# Custom directory
owner/repo2 custom-dir

# Worktree off repo2 with custom dir
@bugfix custom-bugfix --worktree

# Clone off repo2 (no worktree flag)
@clone-branch
EOF

"$WORKSPACE_SCRIPT" -f repos.list >/dev/null

if command -v jq >/dev/null 2>&1; then
  paths=$(jq -r '.folders[].path' entire-project.code-workspace | sort)
  # Expected paths relative to complex-test (which is inside TEST_DIR)
  # repo1 -> ../repo1
  # @feature (worktree off repo1) -> ../repo1-feature
  # repo2 custom-dir -> ../custom-dir
  # @bugfix (worktree off repo2 custom) -> ../custom-bugfix
  # @clone-branch (clone off repo2) -> ../repo2-clone-branch
  # . (current dir) -> .

  expected=$(printf ".\n../custom-bugfix\n../custom-dir\n../repo1\n../repo1-feature\n../repo2-clone-branch" | sort)

  if [ "$paths" = "$expected" ]; then
    print_pass "Complex paths handled correctly"
  else
    print_fail "Complex paths incorrect"
    print_info "Expected:\n$expected"
    print_info "Got:\n$paths"
  fi
fi

# ============================================
# Test 3: Global flags ignored
# ============================================
print_test "Global flags ignored"

cd "$TEST_DIR"
mkdir -p flags-test
cd flags-test

cat > repos.list <<'EOF'
--public
--worktree
owner/repo1
EOF

"$WORKSPACE_SCRIPT" -f repos.list >/dev/null

if command -v jq >/dev/null 2>&1; then
  paths=$(jq -r '.folders[].path' entire-project.code-workspace | sort)
  expected=$(printf ".\n../repo1" | sort)

  if [ "$paths" = "$expected" ]; then
    print_pass "Global flags ignored correctly"
  else
    print_fail "Global flags caused incorrect paths"
    print_info "Expected:\n$expected"
    print_info "Got:\n$paths"
  fi
fi

# ============================================
# Test 4: Mixed flags on lines
# ============================================
print_test "Mixed flags on lines ignored"

cd "$TEST_DIR"
mkdir -p mixed-flags-test
cd mixed-flags-test

cat > repos.list <<'EOF'
owner/repo1 --public
owner/repo2 --private --codespaces
@feature --worktree --public
EOF

"$WORKSPACE_SCRIPT" -f repos.list >/dev/null

if command -v jq >/dev/null 2>&1; then
  paths=$(jq -r '.folders[].path' entire-project.code-workspace | sort)
  # repo1 --public -> ../repo1
  # repo2 --private -> ../repo2
  # @feature --worktree --public -> ../repo2-feature (fallback is repo2)

  expected=$(printf ".\n../repo1\n../repo2\n../repo2-feature" | sort)

  if [ "$paths" = "$expected" ]; then
    print_pass "Mixed flags handled correctly"
  else
    print_fail "Mixed flags caused incorrect paths"
    print_info "Expected:\n$expected"
    print_info "Got:\n$paths"
  fi
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
