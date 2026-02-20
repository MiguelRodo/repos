#!/usr/bin/env bash
# test-clone-repos-flags.sh — Test that clone-repos.sh handles various flags correctly

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
CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "clone-repos.sh Flags Handling Test"

print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# Setup a local bare repo for testing
cd "$TEST_DIR"
mkdir bare-repo.git
git init --bare -q bare-repo.git
BARE_REPO="$(pwd)/bare-repo.git"

# Create a local repo to run from (so we have a fallback)
mkdir run-dir
cd run-dir
git init -q
git remote add origin "file://$BARE_REPO"

# ============================================
# Test 1: Ignore known create-repos flags without warning
# ============================================
print_test "Ignore --public/--private/--codespaces flags without warning"

cat > repos.list <<EOF
file://$BARE_REPO --public
file://$BARE_REPO --private
file://$BARE_REPO --codespaces
EOF

# Run clone-repos.sh and capture stderr
OUTPUT=$("$CLONE_SCRIPT" -f repos.list 2>&1 || true)

# Check for warnings
if echo "$OUTPUT" | grep -q "Warning: ignoring unknown option"; then
  print_fail "Script emitted warnings for valid flags"
  echo "$OUTPUT" | grep "Warning: ignoring unknown option"
else
  print_pass "Script ignored flags silently"
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
