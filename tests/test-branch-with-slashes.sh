#!/usr/bin/env bash
# test-branch-with-slashes.sh — Test that branches with slashes work correctly
# Tests the sanitize_branch_name function and directory path construction

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

print_header "Branch with Slashes Test Suite"

# ============================================
# Test 1: Sanitize function in clone-repos.sh
# ============================================
print_test "sanitize_branch_name function in clone-repos.sh"

# Source the function from clone-repos.sh
CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"

# Extract and test the sanitize function
if grep -q "sanitize_branch_name" "$CLONE_SCRIPT"; then
  print_info "  Found sanitize_branch_name in clone-repos.sh"
  
  # Test the function by sourcing it in a subshell
  result=$(bash -c "
    $(grep -A 3 '^sanitize_branch_name()' "$CLONE_SCRIPT" | head -4)
    sanitize_branch_name 'feature/new-thing'
  ")
  
  if [ "$result" = "feature-new-thing" ]; then
    print_pass "Sanitize function converts slashes to dashes"
  else
    print_fail "Sanitize function output: '$result' (expected: 'feature-new-thing')"
  fi
else
  print_fail "sanitize_branch_name not found in clone-repos.sh"
fi

# ============================================
# Test 2: Sanitize function in vscode-workspace-add.sh
# ============================================
print_test "sanitize_branch_name function in vscode-workspace-add.sh"

WORKSPACE_SCRIPT="$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh"

if grep -q "sanitize_branch_name" "$WORKSPACE_SCRIPT"; then
  print_info "  Found sanitize_branch_name in vscode-workspace-add.sh"
  
  # Test the function
  result=$(bash -c "
    $(grep -A 3 '^sanitize_branch_name()' "$WORKSPACE_SCRIPT" | head -4)
    sanitize_branch_name 'hotfix/urgent-fix'
  ")
  
  if [ "$result" = "hotfix-urgent-fix" ]; then
    print_pass "Sanitize function converts slashes to dashes"
  else
    print_fail "Sanitize function output: '$result' (expected: 'hotfix-urgent-fix')"
  fi
else
  print_fail "sanitize_branch_name not found in vscode-workspace-add.sh"
fi

# ============================================
# Test 3: Sanitize function in add-branch.sh
# ============================================
print_test "sanitize_branch_name function in add-branch.sh"

ADD_BRANCH_SCRIPT="$PROJECT_ROOT/scripts/add-branch.sh"

if grep -q "sanitize_branch_name" "$ADD_BRANCH_SCRIPT"; then
  print_info "  Found sanitize_branch_name in add-branch.sh"
  
  # Test the function
  result=$(bash -c "
    $(grep -A 3 '^sanitize_branch_name()' "$ADD_BRANCH_SCRIPT" | head -4)
    sanitize_branch_name 'release/v1.0.0'
  ")
  
  if [ "$result" = "release-v1.0.0" ]; then
    print_pass "Sanitize function converts slashes to dashes"
  else
    print_fail "Sanitize function output: '$result' (expected: 'release-v1.0.0')"
  fi
else
  print_fail "sanitize_branch_name not found in add-branch.sh"
fi

# ============================================
# Test 4: Usage of sanitize in clone-repos.sh
# ============================================
print_test "clone-repos.sh uses sanitize when constructing paths"

# Check for safe_ref usage in single-branch clone path
if grep -q 'safe_ref="$(sanitize_branch_name "$ref")"' "$CLONE_SCRIPT" && \
   grep -q '${repo_dir}-${safe_ref}' "$CLONE_SCRIPT"; then
  print_pass "clone-repos.sh sanitizes ref in single-branch clone paths"
else
  print_fail "clone-repos.sh doesn't properly sanitize ref in paths"
fi

# Check for safe_branch usage in worktree path
if grep -q 'safe_branch="$(sanitize_branch_name "$branch")"' "$CLONE_SCRIPT" && \
   grep -q '${repo_base}-${safe_branch}' "$CLONE_SCRIPT"; then
  print_pass "clone-repos.sh sanitizes branch in worktree paths"
else
  print_fail "clone-repos.sh doesn't properly sanitize branch in worktree paths"
fi

# ============================================
# Test 5: Usage of sanitize in vscode-workspace-add.sh
# ============================================
print_test "vscode-workspace-add.sh uses sanitize when constructing paths"

# Check for safe_branch usage
if grep -q 'safe_branch="$(sanitize_branch_name "$branch")"' "$WORKSPACE_SCRIPT" && \
   grep -q '${fallback_repo_name}-${safe_branch}' "$WORKSPACE_SCRIPT"; then
  print_pass "vscode-workspace-add.sh sanitizes branch in paths"
else
  print_fail "vscode-workspace-add.sh doesn't properly sanitize branch"
fi

# Check for safe_ref usage
if grep -q 'safe_ref="$(sanitize_branch_name "$ref")"' "$WORKSPACE_SCRIPT" && \
   grep -q '${repo_name}-${safe_ref}' "$WORKSPACE_SCRIPT"; then
  print_pass "vscode-workspace-add.sh sanitizes ref in paths"
else
  print_fail "vscode-workspace-add.sh doesn't properly sanitize ref"
fi

# ============================================
# Test 6: Usage of sanitize in add-branch.sh
# ============================================
print_test "add-branch.sh uses sanitize when constructing paths"

if grep -q 'SAFE_BRANCH_NAME="$(sanitize_branch_name "$BRANCH_NAME")"' "$ADD_BRANCH_SCRIPT" && \
   grep -q '${REPO_NAME}-${SAFE_BRANCH_NAME}' "$ADD_BRANCH_SCRIPT"; then
  print_pass "add-branch.sh sanitizes BRANCH_NAME in paths"
else
  print_fail "add-branch.sh doesn't properly sanitize BRANCH_NAME"
fi

# ============================================
# Test 7: Test complex branch names
# ============================================
print_test "Complex branch names are sanitized correctly"

# Test various complex branch names
test_cases=(
  "feature/cool-feature:feature-cool-feature"
  "hotfix/urgent/fix:hotfix-urgent-fix"
  "release/1.0/final:release-1.0-final"
  "user/john/dev:user-john-dev"
)

all_passed=true
for test_case in "${test_cases[@]}"; do
  input="${test_case%%:*}"
  expected="${test_case##*:}"
  
  result=$(bash -c "
    $(grep -A 3 '^sanitize_branch_name()' "$CLONE_SCRIPT" | head -4)
    sanitize_branch_name '$input'
  ")
  
  if [ "$result" = "$expected" ]; then
    print_info "  ✓ '$input' → '$result'"
  else
    print_info "  ✗ '$input' → '$result' (expected: '$expected')"
    all_passed=false
  fi
done

if $all_passed; then
  print_pass "All complex branch names sanitized correctly"
else
  print_fail "Some complex branch names not sanitized correctly"
fi

# ============================================
# Test 8: Ensure git branch names remain unchanged
# ============================================
print_test "Git branch names are used as-is (not sanitized)"

# Check that the actual git commands still use the original branch variable
if grep -q 'git.*worktree.*"$branch"' "$CLONE_SCRIPT" && \
   grep -q 'push.*HEAD:"$ref"' "$CLONE_SCRIPT"; then
  print_pass "Git commands use original (unsanitized) branch names"
else
  print_fail "Git commands may be using sanitized branch names"
fi

if grep -q 'git worktree add.*"$BRANCH_NAME"' "$ADD_BRANCH_SCRIPT"; then
  print_pass "add-branch.sh git commands use original BRANCH_NAME"
else
  print_fail "add-branch.sh may be using sanitized branch name in git commands"
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
  echo -e "${RED}Some tests failed. Please review the output above.${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
  echo ""
  echo "The scripts now properly handle branch names with slashes."
  echo "Slashes are converted to dashes in directory names while"
  echo "preserving the original branch name for git operations."
fi
