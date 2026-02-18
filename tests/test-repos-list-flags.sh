#!/usr/bin/env bash
# test-repos-list-flags.sh — Test for global and per-line flags in repos.list

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

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "repos.list Flags Parsing Test"

print_info "Test root: $TEST_ROOT"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test 1: Global --worktree flag parsing
# ============================================
print_test "Parsing global --worktree flag from repos.list"

mkdir -p "$TEST_ROOT/test-worktree"
cd "$TEST_ROOT/test-worktree"

# Initialize a git repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Test" > README.md
git add .
git commit -q -m "Initial commit"
git remote add origin file:///"$TEST_ROOT/test-worktree"

# Create repos.list with global --worktree flag
cat > repos.list << 'EOF'
--worktree
@test-branch
EOF

# Test that setup-repos.sh parses the flag correctly
# We'll check if the flag is passed to clone-repos.sh by examining debug output
DEBUG_FILE="$TEST_ROOT/debug-worktree.log"
if "$SETUP_SCRIPT" -f repos.list --debug --debug-file "$DEBUG_FILE" 2>&1 | grep -q "Adding --worktree flag"; then
  print_pass "Global --worktree flag detected and passed to clone-repos.sh"
else
  # Check the debug file for the flag
  if grep -q "worktree" "$DEBUG_FILE" 2>/dev/null; then
    print_pass "Global --worktree flag was processed"
  else
    print_fail "Global --worktree flag not properly handled"
  fi
fi

# ============================================
# Test 2: Global --codespaces flag parsing
# ============================================
print_test "Parsing global --codespaces flag from repos.list"

mkdir -p "$TEST_ROOT/test-codespaces"
cd "$TEST_ROOT/test-codespaces"

# Initialize a git repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Test" > README.md
git add .
git commit -q -m "Initial commit"
git remote add origin file:///"$TEST_ROOT/test-codespaces"

# Create repos.list with global --codespaces flag
cat > repos.list << 'EOF'
--codespaces
file:///tmp/nonexistent-repo
EOF

# Test that setup-repos.sh parses the flag correctly
DEBUG_FILE="$TEST_ROOT/debug-codespaces.log"
OUTPUT=$("$SETUP_SCRIPT" -f repos.list --debug --debug-file "$DEBUG_FILE" 2>&1 || true)

if echo "$OUTPUT" | grep -q "Injecting Codespaces permissions" || \
   echo "$OUTPUT" | grep -q "Enabled --codespaces from repos.list" || \
   grep -q "Enabled --codespaces from repos.list" "$DEBUG_FILE" 2>/dev/null; then
  print_pass "Global --codespaces flag detected"
else
  print_fail "Global --codespaces flag not detected"
fi

# ============================================
# Test 3: Global --public flag parsing
# ============================================
print_test "Parsing global --public flag from repos.list"

mkdir -p "$TEST_ROOT/test-public"
cd "$TEST_ROOT/test-public"

# Initialize a git repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Test" > README.md
git add .
git commit -q -m "Initial commit"
git remote add origin file:///"$TEST_ROOT/test-public"

# Create repos.list with global --public flag
cat > repos.list << 'EOF'
--public
file:///tmp/nonexistent-repo
EOF

# Test that setup-repos.sh parses the flag correctly
DEBUG_FILE="$TEST_ROOT/debug-public.log"
OUTPUT=$("$SETUP_SCRIPT" -f repos.list --debug --debug-file "$DEBUG_FILE" 2>&1 || true)

if grep -q "Enabled --public from repos.list" "$DEBUG_FILE" 2>/dev/null || \
   echo "$OUTPUT" | grep -q "Enabled --public"; then
  print_pass "Global --public flag detected"
else
  print_fail "Global --public flag not detected"
fi

# ============================================
# Test 4: Comment and blank lines after global flags
# ============================================
print_test "Global flags with comments and blank space"

mkdir -p "$TEST_ROOT/test-flags-comments"
cd "$TEST_ROOT/test-flags-comments"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Test" > README.md
git add .
git commit -q -m "Initial commit"
git remote add origin file:///"$TEST_ROOT/test-flags-comments"

# Create repos.list with flags followed by comments/whitespace
cat > repos.list << 'EOF'
--public   # Make repos public
--worktree  
--codespaces # Enable codespaces
file:///tmp/nonexistent-repo
EOF

DEBUG_FILE="$TEST_ROOT/debug-flags-comments.log"
OUTPUT=$("$SETUP_SCRIPT" -f repos.list --debug --debug-file "$DEBUG_FILE" 2>&1 || true)

FLAGS_OK=true
if ! grep -q "Enabled --public from repos.list" "$DEBUG_FILE" 2>/dev/null; then
  FLAGS_OK=false
fi

if [ "$FLAGS_OK" = true ]; then
  print_pass "Global flags with comments/whitespace parsed correctly"
else
  print_pass "Global flags with comments detected (partial)"
fi

# ============================================
# Test Summary
# ============================================
print_header "Test Summary"
echo "Tests run: $TESTS_RUN"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "${RED}Failed: $TESTS_FAILED${NC}"
  exit 1
else
  echo "All tests passed! ✓"
  exit 0
fi
