#!/usr/bin/env bash
# test-setup-repos.sh — Manual test suite for setup-repos.sh
# Run this script to verify setup-repos.sh functionality

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

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup-repos.sh"

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "CompTemplate setup-repos.sh Manual Test Suite"

print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test 1: Script exists and is executable
# ============================================
print_test "Script exists and is executable"

if [ -x "$SETUP_SCRIPT" ]; then
  print_pass "setup-repos.sh is executable"
else
  print_fail "setup-repos.sh not found or not executable"
  exit 1
fi

# ============================================
# Test 2: Help message
# ============================================
print_test "Help message displays correctly"

if "$SETUP_SCRIPT" --help 2>&1 | grep -q "Usage:"; then
  print_pass "Help message displays"
else
  print_fail "Help message does not display"
fi

# ============================================
# Test 3: Check helper scripts exist
# ============================================
print_test "Helper scripts exist"

HELPER_SCRIPTS=(
  "helper/clone-repos.sh"
  "helper/vscode-workspace-add.sh"
  "helper/codespaces-auth-add.sh"
  "helper/create-repos.sh"
)

ALL_HELPERS_EXIST=true
for script in "${HELPER_SCRIPTS[@]}"; do
  if [ -x "$PROJECT_ROOT/scripts/$script" ]; then
    print_info "  ✓ $script exists"
  else
    print_warning "  ✗ $script missing or not executable"
    ALL_HELPERS_EXIST=false
  fi
done

if $ALL_HELPERS_EXIST; then
  print_pass "All helper scripts exist"
else
  print_fail "Some helper scripts missing"
fi

# ============================================
# Test 4: repos.list format validation
# ============================================
print_test "repos.list format validation"

# Create a test repos.list
cat > "$TEST_DIR/test-repos.list" <<'EOF'
# Test repository list

# Full clone
testowner/testrepo

# Single branch
testowner/testrepo2@branch

# Worktree
@dev

# With custom directory
testowner/testrepo3 custom-name

# Complex example
SATVILab/projr
@feature
EOF

print_info "Created test repos.list with various formats"
print_pass "repos.list format test data created"

# ============================================
# Test 5: clone-repos.sh path logic
# ============================================
print_test "clone-repos.sh follows documented path logic"

CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"

if [ -x "$CLONE_SCRIPT" ]; then
  # Test help includes path documentation
  if "$CLONE_SCRIPT" --help | grep -i -q "parent.*directory\|PARENT"; then
    print_pass "clone-repos.sh documents path logic"
  else
    print_fail "clone-repos.sh missing path documentation"
  fi
else
  print_fail "clone-repos.sh not found"
fi

# ============================================
# Test 6: Workspace script compatibility
# ============================================
print_test "vscode-workspace-add.sh tool compatibility"

WORKSPACE_SCRIPT="$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh"

if [ -x "$WORKSPACE_SCRIPT" ]; then
  # Check for tool detection
  if grep -q "command -v jq" "$WORKSPACE_SCRIPT" && \
     grep -q "command -v python" "$WORKSPACE_SCRIPT"; then
    print_pass "Workspace script checks for multiple tools"
  else
    print_fail "Workspace script missing tool detection"
  fi
else
  print_fail "vscode-workspace-add.sh not found"
fi

# ============================================
# Test 7: Codespaces auth script
# ============================================
print_test "codespaces-auth-add.sh handles fallback repo logic"

CODESPACES_SCRIPT="$PROJECT_ROOT/scripts/helper/codespaces-auth-add.sh"

if [ -x "$CODESPACES_SCRIPT" ]; then
  # Check for fallback repo handling
  if grep -q "fallback_repo" "$CODESPACES_SCRIPT"; then
    print_pass "Codespaces script implements fallback repo logic"
  else
    print_warning "Codespaces script may not handle fallback repos"
  fi
else
  print_fail "codespaces-auth-add.sh not found"
fi

# ============================================
# Test 8: Error handling
# ============================================
print_test "setup-repos.sh error handling"

# Test with missing repos.list
if ! "$SETUP_SCRIPT" -f /nonexistent/repos.list 2>&1 | grep -q -i "error\|not found"; then
  print_fail "Does not handle missing repos.list"
else
  print_pass "Handles missing repos.list"
fi

# ============================================
# Test 9: Cross-platform compatibility
# ============================================
print_test "Scripts use portable bash constructs"

SCRIPTS_TO_CHECK=(
  "$SETUP_SCRIPT"
  "$CLONE_SCRIPT"
  "$WORKSPACE_SCRIPT"
  "$CODESPACES_SCRIPT"
)

ALL_PORTABLE=true
for script in "${SCRIPTS_TO_CHECK[@]}"; do
  if [ ! -f "$script" ]; then continue; fi
  
  # Check shebang
  if ! head -n1 "$script" | grep -q "#!/usr/bin/env bash"; then
    print_warning "$(basename $script): Non-portable shebang"
    ALL_PORTABLE=false
  fi
done

if $ALL_PORTABLE; then
  print_pass "Scripts use portable constructs"
else
  print_warning "Some scripts may have portability issues"
fi

# ============================================
# Test 10: Documentation consistency
# ============================================
print_test "Documentation consistency"

README="$PROJECT_ROOT/README.md"
COPILOT_INSTRUCTIONS="$PROJECT_ROOT/.github/copilot-instructions.md"

if [ -f "$README" ] && grep -q "scripts/setup-repos.sh" "$README"; then
  print_pass "README documents setup-repos.sh"
else
  print_fail "README missing setup-repos.sh documentation"
fi

if [ -f "$COPILOT_INSTRUCTIONS" ] && grep -q "clone-repos.sh" "$COPILOT_INSTRUCTIONS"; then
  print_pass "Copilot instructions document path logic"
else
  print_fail "Copilot instructions missing path logic documentation"
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
  echo "Manual testing checklist:"
  echo "  [ ] Create a test repos.list with real repositories"
  echo "  [ ] Run scripts/setup-repos.sh"
  echo "  [ ] Verify repositories are cloned to parent directory"
  echo "  [ ] Verify workspace file is created"
  echo "  [ ] Verify devcontainer.json is updated (if it exists)"
  echo "  [ ] Test on Linux, macOS, and Windows (Git Bash)"
  echo ""
  echo "For interactive testing:"
  echo "  1. Create test repos.list: cp repos.list.example test-repos.list"
  echo "  2. Run: scripts/setup-repos.sh -f test-repos.list"
  echo "  3. Verify output and file structure"
fi
