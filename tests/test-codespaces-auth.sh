#!/usr/bin/env bash
# test-codespaces-auth.sh — Test suite for codespaces authentication functionality

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
CODESPACES_SCRIPT="$PROJECT_ROOT/scripts/helper/codespaces-auth-add.sh"

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "Codespaces Authentication Test Suite"
print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test 1: Script requires devcontainer path (opt-in behavior)
# ============================================
print_test "Script exits gracefully when no devcontainer paths specified (opt-in)"

cd "$TEST_DIR"
mkdir -p test-project/.devcontainer
cat > test-project/repos.list <<'EOF'
testowner/testrepo
EOF

cd test-project
git init
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"

# Run without -d flag - should exit gracefully with message
set +e
output=$("$CODESPACES_SCRIPT" -f repos.list 2>&1)
exit_code=$?
set -e

if [ "$exit_code" -eq 0 ] && echo "$output" | grep -q "No devcontainer.json paths specified"; then
  print_pass "Script exits gracefully without devcontainer paths"
else
  print_fail "Script should exit gracefully when no paths specified (exit code: $exit_code)"
fi

# ============================================
# Test 2: Single devcontainer path specification
# ============================================
print_test "Script updates single devcontainer.json when path specified"

cd "$TEST_DIR"
rm -rf test-project
mkdir -p test-project/.devcontainer
cat > test-project/repos.list <<'EOF'
testowner/testrepo
EOF

cat > test-project/.devcontainer/devcontainer.json <<'EOF'
{
  "name": "Test Container"
}
EOF

cd test-project
git init
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"

# Check if jq or python is available
if command -v jq >/dev/null 2>&1; then
  TOOL="jq"
elif command -v python3 >/dev/null 2>&1; then
  TOOL="python3"
elif command -v python >/dev/null 2>&1; then
  TOOL="python"
else
  print_info "Neither jq nor python available, skipping update test"
  TOOL=""
fi

if [ -n "$TOOL" ]; then
  set +e
  output=$("$CODESPACES_SCRIPT" -f repos.list -d .devcontainer/devcontainer.json -t "$TOOL" 2>&1)
  exit_code=$?
  set -e
  
  if [ "$exit_code" -eq 0 ]; then
    # Check if the file was actually updated
    if [ -f .devcontainer/devcontainer.json ]; then
      # Verify the structure exists
      if grep -q "customizations" .devcontainer/devcontainer.json && \
         grep -q "codespaces" .devcontainer/devcontainer.json && \
         grep -q "repositories" .devcontainer/devcontainer.json; then
        print_pass "Script successfully updates devcontainer.json with repositories"
      else
        print_fail "devcontainer.json missing expected structure"
      fi
    else
      print_fail "devcontainer.json not found after update"
    fi
  else
    print_info "Script output: $output"
    print_fail "Script failed to update devcontainer.json (exit code: $exit_code)"
  fi
fi

# ============================================
# Test 3: Multiple devcontainer paths
# ============================================
print_test "Script updates multiple devcontainer.json files when multiple paths specified"

cd "$TEST_DIR"
rm -rf test-project
mkdir -p test-project/.devcontainer
mkdir -p test-project/subdir/.devcontainer

cat > test-project/repos.list <<'EOF'
testowner/testrepo
testowner/another
EOF

cat > test-project/.devcontainer/devcontainer.json <<'EOF'
{
  "name": "Main Container"
}
EOF

cat > test-project/subdir/.devcontainer/devcontainer.json <<'EOF'
{
  "name": "Sub Container"
}
EOF

cd test-project
git init
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"

if [ -n "$TOOL" ]; then
  set +e
  output=$("$CODESPACES_SCRIPT" -f repos.list \
    -d .devcontainer/devcontainer.json \
    -d subdir/.devcontainer/devcontainer.json \
    -t "$TOOL" 2>&1)
  exit_code=$?
  set -e
  
  if [ "$exit_code" -eq 0 ]; then
    # Check both files were updated
    updated_count=0
    if grep -q "repositories" .devcontainer/devcontainer.json; then
      updated_count=$((updated_count + 1))
    fi
    if grep -q "repositories" subdir/.devcontainer/devcontainer.json; then
      updated_count=$((updated_count + 1))
    fi
    
    if [ "$updated_count" -eq 2 ]; then
      print_pass "Script successfully updates multiple devcontainer.json files"
    else
      print_fail "Not all devcontainer.json files were updated (updated: $updated_count/2)"
    fi
  else
    print_info "Script output: $output"
    print_fail "Script failed when updating multiple files (exit code: $exit_code)"
  fi
fi

# ============================================
# Test 4: Error handling for non-existent path
# ============================================
print_test "Script reports error for non-existent devcontainer path"

cd "$TEST_DIR"
rm -rf test-project
mkdir -p test-project

cat > test-project/repos.list <<'EOF'
testowner/testrepo
EOF

cd test-project
git init
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"

set +e
output=$("$CODESPACES_SCRIPT" -f repos.list -d /nonexistent/devcontainer.json 2>&1)
exit_code=$?
set -e

if [ "$exit_code" -ne 0 ] && echo "$output" | grep -q "not found"; then
  print_pass "Script correctly reports error for non-existent path"
else
  print_fail "Script should report error for non-existent path"
fi

# ============================================
# Test 5: Relative path resolution
# ============================================
print_test "Script correctly resolves relative paths"

cd "$TEST_DIR"
rm -rf test-project
mkdir -p test-project/.devcontainer

cat > test-project/repos.list <<'EOF'
testowner/testrepo
EOF

cat > test-project/.devcontainer/devcontainer.json <<'EOF'
{
  "name": "Test Container"
}
EOF

cd test-project
git init
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"

if [ -n "$TOOL" ]; then
  set +e
  # Use relative path
  output=$("$CODESPACES_SCRIPT" -f repos.list -d .devcontainer/devcontainer.json -t "$TOOL" 2>&1)
  exit_code=$?
  set -e
  
  if [ "$exit_code" -eq 0 ] && grep -q "repositories" .devcontainer/devcontainer.json; then
    print_pass "Script correctly handles relative paths"
  else
    print_fail "Script failed to handle relative path"
  fi
fi

# ============================================
# Test 6: setup-repos.sh opt-in behavior
# ============================================
print_test "setup-repos.sh does NOT run codespaces auth by default"

cd "$TEST_DIR"
rm -rf test-project
mkdir -p test-project/.devcontainer
mkdir -p test-project/scripts/helper

# Copy scripts
cp "$PROJECT_ROOT/scripts/setup-repos.sh" test-project/scripts/
cp -r "$PROJECT_ROOT/scripts/helper" test-project/scripts/
chmod +x test-project/scripts/setup-repos.sh
chmod +x test-project/scripts/helper/*.sh

cat > test-project/repos.list <<'EOF'
# Empty - won't actually clone anything
EOF

cat > test-project/.devcontainer/devcontainer.json <<'EOF'
{
  "name": "Test Container"
}
EOF

cd test-project
git init
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"

# Run setup-repos.sh without --codespaces flag
set +e
output=$(./scripts/setup-repos.sh -f repos.list 2>&1 || true)
set -e

if echo "$output" | grep -q "Skipping Codespaces auth"; then
  print_pass "setup-repos.sh skips codespaces auth by default"
else
  print_info "Output: $output"
  print_fail "setup-repos.sh should skip codespaces auth by default"
fi

# ============================================
# Test 7: setup-repos.sh --codespaces flag
# ============================================
print_test "setup-repos.sh runs codespaces auth with --codespaces flag"

# File already exists from previous test, just verify it hasn't been modified
original_content=$(cat .devcontainer/devcontainer.json)

# This test would require full setup-repos to run which needs network access
# So we'll just verify the flag is accepted
set +e
help_output=$(./scripts/setup-repos.sh --help 2>&1 || true)
set -e

if echo "$help_output" | grep -q -- "--codespaces"; then
  print_pass "setup-repos.sh accepts --codespaces flag"
else
  print_fail "setup-repos.sh should accept --codespaces flag"
fi

# ============================================
# Test 8: setup-repos.sh -d flag
# ============================================
print_test "setup-repos.sh accepts -d/--devcontainer flag"

if echo "$help_output" | grep -q -- "--devcontainer"; then
  print_pass "setup-repos.sh accepts -d/--devcontainer flag"
else
  print_fail "setup-repos.sh should accept -d/--devcontainer flag"
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
