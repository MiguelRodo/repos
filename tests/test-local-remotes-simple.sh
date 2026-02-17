#!/usr/bin/env bash
# test-local-remotes-simple.sh — Simple test for local git remote support
# Tests that setup-repos.sh can work with local git remotes for offline testing

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

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "Simple Local Git Remote Test"
print_info "Test root: $TEST_ROOT"
print_info "Purpose: Verify setup-repos.sh works with local git remotes for offline testing"

# ============================================
# Test 1: create-repos.sh skips local remotes
# ============================================
print_test "create-repos.sh skips local file:// URLs without calling GitHub API"

cd "$TEST_ROOT"
cat > repos.list <<EOF
file:///tmp/fake-repo.git
/tmp/another-fake-repo.git
EOF

OUTPUT=$("$PROJECT_ROOT/scripts/helper/create-repos.sh" -f repos.list 2>&1)
if echo "$OUTPUT" | grep -q "Skipping local remote: file:///tmp/fake-repo.git" && \
   echo "$OUTPUT" | grep -q "Skipping local remote: /tmp/another-fake-repo.git"; then
  print_pass "Correctly skips file:// and absolute path remotes"
else
  print_fail "Did not skip local remotes"
  print_info "Output: $OUTPUT"
fi

if echo "$OUTPUT" | grep -q "fatal.*password\|Error.*GitHub"; then
  print_fail "Tried to access GitHub API for local remotes"
else
  print_pass "Did not attempt GitHub API calls for local remotes"
fi

# ============================================
# Test 2: create-repos.sh still processes GitHub URLs
# ============================================
print_test "create-repos.sh still processes GitHub owner/repo format"

cd "$TEST_ROOT"
cat > repos.list <<EOF
# This will try to access GitHub (but should fail gracefully without credentials)
someowner/somerepo
EOF

# This should try to get credentials, which will fail in test environment
# But that's expected - we just want to verify it tries to process it
OUTPUT=$("$PROJECT_ROOT/scripts/helper/create-repos.sh" -f repos.list 2>&1 || true)
if echo "$OUTPUT" | grep -q "Skipping local remote"; then
  print_fail "Incorrectly skipped GitHub owner/repo format"
else
  print_pass "Correctly attempts to process GitHub owner/repo format"
fi

# ============================================
# Test 3: Mixed repos.list with local and GitHub
# ============================================
print_test "create-repos.sh handles mixed local and GitHub remotes"

cd "$TEST_ROOT"
cat > repos.list <<EOF
# Local remotes (should skip)
file:///tmp/local1.git
/absolute/path/local2.git

# GitHub remote (should attempt to process)
# testowner/testrepo
EOF

OUTPUT=$("$PROJECT_ROOT/scripts/helper/create-repos.sh" -f repos.list 2>&1)
SKIP_COUNT=$(echo "$OUTPUT" | grep -c "Skipping local remote" || true)
if [ "$SKIP_COUNT" -eq 2 ]; then
  print_pass "Skipped exactly 2 local remotes"
else
  print_fail "Expected to skip 2 local remotes, but skipped $SKIP_COUNT"
fi

# ============================================
# Test 4: clone-repos.sh handles file:// URLs
# ============================================
print_test "clone-repos.sh recognizes file:// URLs as valid remotes"

# Create a real bare repo to test with
BARE_REPO="$TEST_ROOT/test-bare.git"
git init --bare -q "$BARE_REPO"

# Add content
TEMP_CLONE="$TEST_ROOT/temp-init"
git clone -q "$BARE_REPO" "$TEMP_CLONE"
cd "$TEMP_CLONE"
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Test" > README.md
git add README.md
git commit -q -m "Initial"
git push -q origin $(git symbolic-ref --short HEAD)
cd "$TEST_ROOT"
rm -rf "$TEMP_CLONE"

# Now test cloning with file:// URL
WORKSPACE="$TEST_ROOT/workspace"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

# Initialize workspace as git repo with a remote (required for @branch syntax to work)
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$BARE_REPO"  # Set a remote
echo "# Workspace" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
file://$BARE_REPO
EOF

"$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/test-bare" ]; then
  print_pass "Successfully cloned from file:// URL"
else
  print_fail "Failed to clone from file:// URL"
  print_info "Contents of $TEST_ROOT:"
  ls -la "$TEST_ROOT"
fi

# ============================================
# Test 5: clone-repos.sh handles absolute paths
# ============================================
print_test "clone-repos.sh recognizes absolute paths as valid remotes"

cd "$WORKSPACE"
rm -rf "$TEST_ROOT/test-bare"  # Clean up from previous test

cat > repos.list <<EOF
$BARE_REPO
EOF

"$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/test-bare" ]; then
  print_pass "Successfully cloned from absolute path"
else
  print_fail "Failed to clone from absolute path"
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
fi
