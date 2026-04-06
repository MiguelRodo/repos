#!/usr/bin/env bash
# test-vscode-workspace-unit.sh — Unit tests for vscode-workspace-add.sh functions

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

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_SCRIPT="$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh"

# Source the script (source guard allows this)
# shellcheck source=scripts/helper/vscode-workspace-add.sh
source "$WORKSPACE_SCRIPT"

print_header "vscode-workspace-add.sh Unit Tests"

# ============================================
# Test: validate_target_dir
# ============================================
print_header "Testing validate_target_dir"

test_validate_target_dir() {
  local input="$1"
  local expected_exit="$2"
  local description="$3"

  print_test "$description (input: '$input')"

  # Run in subshell to capture stderr and avoid exit on failure if set -e was on
  if ( validate_target_dir "$input" > /dev/null 2>&1 ); then
    actual_exit=0
  else
    actual_exit=1
  fi

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    print_pass "Result matches expected ($expected_exit)"
  else
    print_fail "Result mismatch. Expected $expected_exit, got $actual_exit"
  fi
}

# Happy paths
test_validate_target_dir "my-repo" 0 "Valid simple directory"
test_validate_target_dir "repos/my-repo" 0 "Valid nested directory"
test_validate_target_dir "repo.name" 0 "Valid directory with dot"
test_validate_target_dir "" 0 "Empty directory (allowed)"

# Invalid paths (absolute)
test_validate_target_dir "/absolute/path" 1 "Invalid absolute path"
test_validate_target_dir "/" 1 "Invalid root path"

# Invalid paths (traversal)
test_validate_target_dir ".." 1 "Invalid double dot"
test_validate_target_dir "../outside" 1 "Invalid parent traversal"
test_validate_target_dir "repo/../outside" 1 "Invalid nested traversal"
test_validate_target_dir "path/.." 1 "Invalid trailing traversal"
test_validate_target_dir "some..thing" 1 "Invalid path containing .."

# ============================================
# Summary
# ============================================
print_header "Unit Test Summary"

echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
  echo ""
  echo -e "${RED}Some unit tests failed.${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}All unit tests passed!${NC}"
fi
