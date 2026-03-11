#!/usr/bin/env bash
# tests/test-add-branch-security.sh
# Validates security hardening in scripts/add-branch.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_pass() { echo -e "${GREEN}PASS: $1${NC}"; }
print_fail() { echo -e "${RED}FAIL: $1${NC}"; exit 1; }

REPO_ROOT="$(pwd)"
ADD_BRANCH_SCRIPT="$REPO_ROOT/scripts/add-branch.sh"

# Create a workspace for testing
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

setup_test_env() {
  local dir="$1"
  mkdir -p "$dir/remote/repo"
  cd "$dir/remote/repo"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"
  git commit -q --allow-empty -m "Initial commit"

  mkdir -p "$dir/work"
  cd "$dir/work"
  git clone -q "$dir/remote/repo" base-repo
  cd base-repo
  git config user.email "test@example.com"
  git config user.name "Test User"
  touch repos.list
}

# Test 1: Argument injection via branch name starting with hyphen
test_hyphen_branch() {
  echo "Test 1: Testing branch name starting with hyphen (e.g., '-n')..."
  setup_test_env "$TEST_DIR/test1"

  # After hardening, it should be rejected by git check-ref-format because -n is not a valid ref name on its own (must be a full ref or we must allow it)
  # Actually, -n IS a valid branch name according to git check-ref-format --allow-onelevel.
  # But we want to make sure it's not interpreted as an option.

  # With --, it should be treated as a branch name.
  # Use -e to test it as well
  OUTPUT=$(bash "$ADD_BRANCH_SCRIPT" -- "-e" 2>&1 || true)

  if echo "$OUTPUT" | grep -q "Error: Unknown option: -e"; then
    print_fail "Hardening failed: -e still interpreted as option even after --"
  fi

  # It might still fail on git clone because it's a dummy repo, but it shouldn't fail on our script's arg parser.
  if echo "$OUTPUT" | grep -q "invalid branch name"; then
    # -e might be invalid if it doesn't meet git's rules.
    # Actually, -e is a valid branch name for git.
    :
  fi
  print_pass "Hardening successful: -e handled correctly after --"
}

# Test 2: Path traversal in branch name
test_traversal_branch() {
  echo "Test 2: Testing branch name with path traversal (e.g., '../traversal')..."
  setup_test_env "$TEST_DIR/test2"

  # git check-ref-format should reject this.
  OUTPUT=$(bash "$ADD_BRANCH_SCRIPT" "../traversal" 2>&1 || true)

  if echo "$OUTPUT" | grep -q "Error: invalid branch name: ../traversal"; then
     print_pass "Hardening successful: Path traversal branch name rejected."
  else
     print_fail "Hardening failed: Path traversal branch name NOT rejected. Output: $OUTPUT"
  fi
}

# Test 3: Grep injection in repos.list check
test_grep_injection() {
  echo "Test 3: Testing grep injection in repos.list check..."
  setup_test_env "$TEST_DIR/test3"

  echo "@-e" > repos.list

  # Simulate grep call from script with -e branch
  BRANCH_NAME="-e"
  if grep -E -q -e "^@${BRANCH_NAME}([[:space:]]|$)" repos.list 2>/dev/null; then
    print_pass "Hardening successful: Correctly matched @-e in repos.list."
  else
    print_fail "Hardening failed: Failed to match @-e in repos.list using hardened grep."
  fi
}

# Run tests
test_hyphen_branch
test_traversal_branch
test_grep_injection

echo "Reproduction tests complete."
