#!/usr/bin/env bash
# test-update-scripts.sh — Automated test suite for update-scripts.sh
# This test can be run automatically in CI/CD

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
UPDATE_SCRIPT="$PROJECT_ROOT/scripts/update-scripts.sh"

# Create temporary test environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "CompTemplate update-scripts.sh Test Suite"

print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test 1: Script exists and is executable
# ============================================
print_test "Script exists and is executable"

if [ -x "$UPDATE_SCRIPT" ]; then
  print_pass "update-scripts.sh is executable"
else
  print_fail "update-scripts.sh not found or not executable"
  exit 1
fi

# ============================================
# Test 2: Help message
# ============================================
print_test "Help message displays correctly"

if "$UPDATE_SCRIPT" --help 2>&1 | grep -q "Usage:"; then
  print_pass "Help message displays"
else
  print_fail "Help message does not display"
fi

# ============================================
# Test 3: Help mentions all scripts, not just helper
# ============================================
print_test "Help text reflects updating all scripts"

HELP_OUTPUT=$("$UPDATE_SCRIPT" --help 2>&1)

if echo "$HELP_OUTPUT" | grep -q "all scripts from scripts/ directory"; then
  print_pass "Help mentions updating all scripts"
else
  print_fail "Help does not mention updating all scripts"
fi

if echo "$HELP_OUTPUT" | grep -q "including helper/ subdirectory"; then
  print_pass "Help mentions helper subdirectory"
else
  print_fail "Help does not mention helper subdirectory"
fi

# Should NOT say "only updates helper"
if echo "$HELP_OUTPUT" | grep -qi "only.*helper"; then
  print_fail "Help still says 'only helper' - needs update"
else
  print_pass "Help does not say 'only helper'"
fi

# ============================================
# Test 4: Dry-run mode works
# ============================================
print_test "Dry-run mode works without making changes"

# Create a test git repo to avoid "not in git repo" errors
cd "$TEST_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# Copy the update script
mkdir -p scripts
cp "$UPDATE_SCRIPT" scripts/update-scripts.sh
chmod +x scripts/update-scripts.sh

# Create a dummy script file
echo "#!/bin/bash" > scripts/dummy.sh
chmod +x scripts/dummy.sh

# Commit initial state
git add .
git commit -q -m "Initial commit"

# Run dry-run - should not fail or make changes
if scripts/update-scripts.sh --dry-run --force 2>&1 | grep -q "This was a dry run"; then
  print_pass "Dry-run mode executes and shows message"
else
  print_fail "Dry-run mode does not show expected message"
fi

# Check no changes were made
if git diff --quiet && git diff --cached --quiet; then
  print_pass "Dry-run does not modify files"
else
  print_fail "Dry-run modified files"
fi

# ============================================
# Test 5: Script detects uncommitted changes
# ============================================
print_test "Script detects uncommitted changes"

cd "$TEST_DIR"

# Modify a script without committing
echo "# modified" >> scripts/dummy.sh

# Should fail without --force
if scripts/update-scripts.sh --dry-run 2>&1 | grep -q "uncommitted changes"; then
  print_pass "Detects uncommitted changes"
else
  print_fail "Does not detect uncommitted changes"
fi

# Should work with --force
if scripts/update-scripts.sh --dry-run --force >/dev/null 2>&1; then
  print_pass "--force bypasses uncommitted changes check"
else
  print_fail "--force does not bypass uncommitted changes check"
fi

# Clean up uncommitted changes
git checkout -- scripts/dummy.sh

# ============================================
# Test 6: Verify it lists both main and helper scripts
# ============================================
print_test "Lists both main scripts and helper scripts"

cd "$PROJECT_ROOT"

# Run dry-run and capture output
DRY_RUN_OUTPUT=$("$UPDATE_SCRIPT" --dry-run --force 2>&1)

# Check for main scripts
MAIN_SCRIPTS=("add-branch.sh" "run-pipeline.sh" "setup-repos.sh" "update-branches.sh" "update-scripts.sh")
MAIN_SCRIPTS_FOUND=true

for script in "${MAIN_SCRIPTS[@]}"; do
  if echo "$DRY_RUN_OUTPUT" | grep -q "$script"; then
    print_info "  ✓ Found main script: $script"
  else
    print_info "  ✗ Missing main script: $script"
    MAIN_SCRIPTS_FOUND=false
  fi
done

if $MAIN_SCRIPTS_FOUND; then
  print_pass "All main scripts are listed"
else
  print_fail "Some main scripts are missing"
fi

# Check for helper scripts
HELPER_SCRIPTS=("helper/clone-repos.sh" "helper/vscode-workspace-add.sh" "helper/codespaces-auth-add.sh")
HELPER_SCRIPTS_FOUND=true

for script in "${HELPER_SCRIPTS[@]}"; do
  if echo "$DRY_RUN_OUTPUT" | grep -q "$script"; then
    print_info "  ✓ Found helper script: $script"
  else
    print_info "  ✗ Missing helper script: $script"
    HELPER_SCRIPTS_FOUND=false
  fi
done

if $HELPER_SCRIPTS_FOUND; then
  print_pass "Helper scripts are listed with subdirectory path"
else
  print_fail "Some helper scripts are missing"
fi

# ============================================
# Test 7: Invalid options are rejected
# ============================================
print_test "Invalid options are rejected"

if "$UPDATE_SCRIPT" --invalid-option 2>&1 | grep -q -i "error\|unknown"; then
  print_pass "Invalid options are rejected"
else
  print_fail "Invalid options are not rejected"
fi

# ============================================
# Test 8: Branch option is accepted
# ============================================
print_test "Branch option is accepted"

# Just check that it doesn't error on the option parsing
if "$UPDATE_SCRIPT" --branch nonexistent-branch --dry-run --force 2>&1 | grep -q "branch: nonexistent-branch"; then
  print_pass "Branch option is accepted"
else
  print_fail "Branch option is not properly handled"
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
fi
