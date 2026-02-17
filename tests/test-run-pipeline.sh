#!/usr/bin/env bash
# test-run-pipeline.sh — Automated test suite for run-pipeline.sh
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
PIPELINE_SCRIPT="$PROJECT_ROOT/scripts/run-pipeline.sh"

# Create temporary test environment
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "CompTemplate run-pipeline.sh Automated Test Suite"

print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# Create test project structure
cd "$TEST_DIR"
mkdir -p test-project/{.devcontainer,scripts/helper}

# Create minimal repos.list
cat > test-project/repos.list <<'EOF'
# Test repositories
test-repo1
test-repo2
EOF

# Create test repositories
for repo in test-repo1 test-repo2; do
  mkdir -p "$repo"
  cd "$repo"
  git init >/dev/null 2>&1
  git config user.name "Test User"
  git config user.email "test@example.com"
  
  # Create a run.sh script
  cat > run.sh <<'RUNSH'
#!/usr/bin/env bash
echo "Running $(basename $(pwd))"
touch .test-executed
RUNSH
  chmod +x run.sh
  
  git add .
  git commit -m "Initial commit" >/dev/null 2>&1
  cd ..
done

# Create workspace file
cat > test-project/entire-project.code-workspace <<'EOF'
{
  "folders": [
    {"path": "."},
    {"path": "../test-repo1"},
    {"path": "../test-repo2"}
  ]
}
EOF

# Copy pipeline script
cp "$PIPELINE_SCRIPT" test-project/scripts/

# ============================================
# Test 1: Script exists and is executable
# ============================================
print_test "Script exists and is executable"

if [ -x test-project/scripts/run-pipeline.sh ]; then
  print_pass "run-pipeline.sh is executable"
else
  print_fail "run-pipeline.sh not found or not executable"
  exit 1
fi

# ============================================
# Test 2: Help message
# ============================================
print_test "Help message displays correctly"

if test-project/scripts/run-pipeline.sh --help 2>&1 | grep -q "Usage:"; then
  print_pass "Help message displays"
else
  print_fail "Help message does not display"
fi

# ============================================
# Test 3: Dry-run mode
# ============================================
print_test "Dry-run mode (--dry-run)"

cd test-project
if scripts/run-pipeline.sh --dry-run --skip-setup 2>&1 | grep -q "DRY-RUN"; then
  print_pass "Dry-run mode works"
else
  print_fail "Dry-run mode not working"
fi
cd ..

# ============================================
# Test 4: Skip setup flag
# ============================================
print_test "Skip setup flag (--skip-setup)"

cd test-project
if scripts/run-pipeline.sh --skip-setup --skip-deps --dry-run 2>&1 | grep -q "Skipping setup"; then
  print_pass "Skip setup flag works"
else
  print_fail "Skip setup flag not working"
fi
cd ..

# ============================================
# Test 5: Skip deps flag
# ============================================
print_test "Skip deps flag (--skip-deps)"

cd test-project
if scripts/run-pipeline.sh --skip-setup --skip-deps --dry-run 2>&1 | grep -q "Skipping.*dependencies"; then
  print_pass "Skip deps flag works"
else
  print_fail "Skip deps flag not working"
fi
cd ..

# ============================================
# Test 6: Execute run.sh scripts
# ============================================
print_test "Execute run.sh scripts in repositories"

cd test-project

# Remove any previous test markers
rm -f ../test-repo1/.test-executed ../test-repo2/.test-executed

# Run pipeline (skip setup and deps, just execute)
if scripts/run-pipeline.sh --skip-setup --skip-deps 2>&1; then
  if [ -f ../test-repo1/.test-executed ] && [ -f ../test-repo2/.test-executed ]; then
    print_pass "run.sh scripts executed in all repos"
  else
    print_fail "run.sh scripts not executed"
    print_info "test-repo1: $([ -f ../test-repo1/.test-executed ] && echo "✓" || echo "✗")"
    print_info "test-repo2: $([ -f ../test-repo2/.test-executed ] && echo "✓" || echo "✗")"
  fi
else
  print_fail "Pipeline execution failed"
fi
cd ..

# ============================================
# Test 7: Include filter
# ============================================
print_test "Include filter (--include)"

cd test-project

# Remove test markers
rm -f ../test-repo1/.test-executed ../test-repo2/.test-executed

# Run only test-repo1
if scripts/run-pipeline.sh --skip-setup --skip-deps --include "test-repo1" 2>&1; then
  if [ -f ../test-repo1/.test-executed ] && [ ! -f ../test-repo2/.test-executed ]; then
    print_pass "Include filter works correctly"
  else
    print_fail "Include filter not working"
    print_info "test-repo1: $([ -f ../test-repo1/.test-executed ] && echo "✓" || echo "✗")"
    print_info "test-repo2: $([ -f ../test-repo2/.test-executed ] && echo "✓" || echo "✗")"
  fi
else
  print_fail "Pipeline with include filter failed"
fi
cd ..

# ============================================
# Test 8: Exclude filter
# ============================================
print_test "Exclude filter (--exclude)"

cd test-project

# Remove test markers
rm -f ../test-repo1/.test-executed ../test-repo2/.test-executed

# Exclude test-repo1
if scripts/run-pipeline.sh --skip-setup --skip-deps --exclude "test-repo1" 2>&1; then
  if [ ! -f ../test-repo1/.test-executed ] && [ -f ../test-repo2/.test-executed ]; then
    print_pass "Exclude filter works correctly"
  else
    print_fail "Exclude filter not working"
    print_info "test-repo1: $([ -f ../test-repo1/.test-executed ] && echo "✓" || echo "✗")"
    print_info "test-repo2: $([ -f ../test-repo2/.test-executed ] && echo "✓" || echo "✗")"
  fi
else
  print_fail "Pipeline with exclude filter failed"
fi
cd ..

# ============================================
# Test 9: Missing workspace file handling
# ============================================
print_test "Missing workspace file handling"

cd test-project
mv entire-project.code-workspace entire-project.code-workspace.bak

if scripts/run-pipeline.sh --skip-setup --skip-deps 2>&1 | grep -q -i "workspace.*not.*found\|cannot"; then
  print_pass "Handles missing workspace file gracefully"
else
  print_fail "Does not handle missing workspace file"
fi

mv entire-project.code-workspace.bak entire-project.code-workspace
cd ..

# ============================================
# Test 10: No run.sh present
# ============================================
print_test "Handling repositories without run.sh"

mkdir -p test-repo3
cd test-repo3
git init >/dev/null 2>&1
git config user.name "Test User"
git config user.email "test@example.com"
echo "test" > README.md
git add .
git commit -m "Initial commit" >/dev/null 2>&1
cd ..

# Update workspace
cat > test-project/entire-project.code-workspace <<'EOF'
{
  "folders": [
    {"path": "."},
    {"path": "../test-repo3"}
  ]
}
EOF

cd test-project
if scripts/run-pipeline.sh --skip-setup --skip-deps 2>&1 | grep -q "No run.sh found"; then
  print_pass "Handles repos without run.sh"
else
  print_fail "Does not properly handle repos without run.sh"
fi
cd ..

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
  echo -e "${GREEN}✅ All tests passed!${NC}"
  echo ""
  echo "The run-pipeline.sh script is working correctly."
fi
