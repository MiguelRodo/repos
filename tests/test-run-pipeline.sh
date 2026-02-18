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
if scripts/run-pipeline.sh --dry-run 2>&1 | grep -q "DRY-RUN"; then
  print_pass "Dry-run mode works"
else
  print_fail "Dry-run mode not working"
fi
cd ..

# ============================================
# Test 4: Skip setup flag
# ============================================
print_test "Ensure setup flag (--ensure-setup)"

cd test-project
# With --ensure-setup, it should attempt to run setup (not show the default skip message)
output=$(scripts/run-pipeline.sh --ensure-setup --skip-deps --dry-run 2>&1)
if echo "$output" | grep -q "Skipping setup step (default"; then
  print_fail "Ensure setup flag not working"
else
  print_pass "Ensure setup flag works"
fi
cd ..

# ============================================
# Test 5: Skip deps flag
# ============================================
print_test "Skip deps flag (--skip-deps)"

cd test-project
if scripts/run-pipeline.sh --skip-deps --dry-run 2>&1 | grep -q "Skipping.*dependencies"; then
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
if scripts/run-pipeline.sh --skip-deps 2>&1; then
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
if scripts/run-pipeline.sh --skip-deps --include "test-repo1" 2>&1; then
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
if scripts/run-pipeline.sh --skip-deps --exclude "test-repo1" 2>&1; then
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
# Test 9: Missing workspace file with fully-specified format
# ============================================
print_test "Missing workspace file handling (fully-specified format)"

cd test-project
mv entire-project.code-workspace entire-project.code-workspace.bak

# Create a fully-specified repos.list (contains '/') so workspace file is required
cat > repos-full.list <<'EOF'
# Fully-specified format
org/test-repo1
org/test-repo2
EOF

if scripts/run-pipeline.sh --skip-deps -f repos-full.list 2>&1 | grep -q -i "workspace.*not.*found\|cannot"; then
  print_pass "Handles missing workspace file gracefully"
else
  print_fail "Does not handle missing workspace file"
fi

rm -f repos-full.list
mv entire-project.code-workspace.bak entire-project.code-workspace
cd ..

# ============================================
# Test 10: No run.sh present (concise format)
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

# Create a concise list pointing to test-repo3 (no run.sh)
cat > test-project/repos-no-run.list <<'EOF'
test-repo3
EOF

cd test-project
if scripts/run-pipeline.sh --skip-deps -f repos-no-run.list 2>&1 | grep -q "no run.sh found\|0 succeeded.*0 failed.*1 skipped"; then
  print_pass "Handles repos without run.sh"
else
  print_fail "Does not properly handle repos without run.sh"
fi
rm -f repos-no-run.list
cd ..

# ============================================
# Test 11: --script flag with custom script
# ============================================
print_test "--script flag runs a custom script"

# Create a custom script in test-repo1
cat > test-repo1/pipeline.sh <<'PIPELINESH'
#!/usr/bin/env bash
echo "Running pipeline.sh in $(basename $(pwd))"
touch .test-pipeline-executed
PIPELINESH
chmod +x test-repo1/pipeline.sh

# Restore workspace to include both repos
cat > test-project/entire-project.code-workspace <<'EOF'
{
  "folders": [
    {"path": "."},
    {"path": "../test-repo1"},
    {"path": "../test-repo2"}
  ]
}
EOF

rm -f test-repo1/.test-pipeline-executed

cd test-project
if scripts/run-pipeline.sh --skip-deps --script pipeline.sh 2>&1; then
  if [ -f ../test-repo1/.test-pipeline-executed ]; then
    print_pass "--script flag runs the correct script"
  else
    print_fail "--script flag did not execute the custom script"
  fi
else
  # Non-zero exit is expected since test-repo2 won't have pipeline.sh
  if [ -f ../test-repo1/.test-pipeline-executed ]; then
    print_pass "--script flag runs the correct script"
  else
    print_fail "--script flag did not execute the custom script"
  fi
fi
rm -f ../test-repo1/.test-pipeline-executed ../test-repo1/pipeline.sh
cd ..

# ============================================
# Test 12: --continue-on-error continues on failure
# ============================================
print_test "--continue-on-error continues past failures"

# Create a failing run.sh in test-repo1
cat > test-repo1/run.sh <<'RUNSH'
#!/usr/bin/env bash
echo "Failing in $(basename $(pwd))"
exit 1
RUNSH
chmod +x test-repo1/run.sh

rm -f test-repo2/.test-executed

cd test-project
output=$(scripts/run-pipeline.sh --skip-deps --continue-on-error 2>&1 || true)
if echo "$output" | grep -q "failed (exit code 1)" && [ -f ../test-repo2/.test-executed ]; then
  print_pass "--continue-on-error continues and reports failures"
else
  print_fail "--continue-on-error did not continue past failure"
  print_info "Output: $output"
  print_info "test-repo2 executed: $([ -f ../test-repo2/.test-executed ] && echo '✓' || echo '✗')"
fi
cd ..

# Restore test-repo1/run.sh
cat > test-repo1/run.sh <<'RUNSH'
#!/usr/bin/env bash
echo "Running $(basename $(pwd))"
touch .test-executed
RUNSH
chmod +x test-repo1/run.sh

# ============================================
# Test 13: Concise format list file
# ============================================
print_test "Concise format list file"

rm -f test-repo1/.test-executed test-repo2/.test-executed

cat > test-project/repos-concise.list <<'EOF'
test-repo1
test-repo2
EOF

cd test-project
if scripts/run-pipeline.sh --skip-deps -f repos-concise.list 2>&1; then
  if [ -f ../test-repo1/.test-executed ] && [ -f ../test-repo2/.test-executed ]; then
    print_pass "Concise format list file works"
  else
    print_fail "Concise format did not execute scripts"
  fi
else
  print_fail "Concise format pipeline failed"
fi
rm -f repos-concise.list
cd ..

# ============================================
# Test 14: Concise format with per-line script name
# ============================================
print_test "Concise format with per-line script name"

# Create a custom script in test-repo1
cat > test-repo1/custom.sh <<'CUSTOMSH'
#!/usr/bin/env bash
echo "Running custom.sh in $(basename $(pwd))"
touch .test-custom-executed
CUSTOMSH
chmod +x test-repo1/custom.sh

rm -f test-repo1/.test-custom-executed test-repo2/.test-executed

cat > test-project/repos-custom.list <<'EOF'
test-repo1 custom.sh
test-repo2
EOF

cd test-project
if scripts/run-pipeline.sh --skip-deps -f repos-custom.list 2>&1; then
  if [ -f ../test-repo1/.test-custom-executed ] && [ -f ../test-repo2/.test-executed ]; then
    print_pass "Concise format per-line script name works"
  else
    print_fail "Concise format per-line script name did not work"
    print_info "test-repo1 custom.sh: $([ -f ../test-repo1/.test-custom-executed ] && echo '✓' || echo '✗')"
    print_info "test-repo2 run.sh: $([ -f ../test-repo2/.test-executed ] && echo '✓' || echo '✗')"
  fi
else
  print_fail "Concise format with per-line script pipeline failed"
fi
rm -f repos-custom.list ../test-repo1/custom.sh
cd ..

# ============================================
# Test 15: Summary output format
# ============================================
print_test "Pipeline summary output format"

rm -f test-repo1/.test-executed test-repo2/.test-executed

cd test-project
output=$(scripts/run-pipeline.sh --skip-deps 2>&1)
if echo "$output" | grep -q "=== Pipeline Summary ===" && echo "$output" | grep -q "Total:.*repositories"; then
  print_pass "Pipeline summary is printed"
else
  print_fail "Pipeline summary not found in output"
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
