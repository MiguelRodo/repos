#!/usr/bin/env bash
# test-fallback-repo-worktree.sh — Test fallback repo logic for worktrees
# Tests that:
# 1. Fallback repo is updated correctly when cloning with @branch and custom target
# 2. Branch existence messages are shown when creating worktrees
# 3. Worktrees use the correct base repo (the one with custom target, not default name)

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

print_header "Fallback Repo & Worktree Test"
print_info "Test root: $TEST_ROOT"
print_info "Purpose: Verify fallback repo logic and branch existence messages"

# ============================================
# Setup: Create local bare repos for testing
# ============================================
print_header "Setup: Creating local test repositories"

REMOTE_ROOT="$TEST_ROOT/remotes"
mkdir -p "$REMOTE_ROOT"

# Create upstream repo with multiple branches
UPSTREAM_REPO="$REMOTE_ROOT/lectures.git"
git init --bare "$UPSTREAM_REPO"

# Create a temporary clone to set up branches
TEMP_CLONE="$TEST_ROOT/temp-clone"
git clone "$UPSTREAM_REPO" "$TEMP_CLONE"
cd "$TEMP_CLONE"
git config user.email "test@example.com"
git config user.name "Test User"

# Create initial commit on master (will be default branch)
echo "Initial content" > README.md
git add README.md
git commit -m "Initial commit"
git push origin HEAD

# Create slides branch
git checkout -b slides-2026-sta5069z
echo "Slides content" > slides.md
git add slides.md
git commit -m "Add slides"
git push origin slides-2026-sta5069z

# Note: data-2026-sta5069z branch does NOT exist yet (will be created by clone-repos.sh)

cd "$TEST_ROOT"
rm -rf "$TEMP_CLONE"

print_pass "Created upstream repo with branches: master, slides-2026-sta5069z"

# Create another repo for testing
EVAL_REPO="$REMOTE_ROOT/eval.git"
git init --bare "$EVAL_REPO"

TEMP_CLONE="$TEST_ROOT/temp-clone"
git clone "$EVAL_REPO" "$TEMP_CLONE"
cd "$TEMP_CLONE"
git config user.email "test@example.com"
git config user.name "Test User"
echo "Eval content" > README.md
git add README.md
git commit -m "Initial commit"
git push origin HEAD

# Note: 2026-sta5069z branch does NOT exist yet

cd "$TEST_ROOT"
rm -rf "$TEMP_CLONE"

print_pass "Created eval repo with master branch only"

# ============================================
# Test 1: Clone with custom target and worktree
# ============================================
print_test "Clone owner/repo@branch with custom target, then create worktree"

WORK_DIR="$TEST_ROOT/work1"
mkdir -p "$WORK_DIR/sta5069z"
cd "$WORK_DIR/sta5069z"

# Initialize this as a git repo (to provide current repo context)
git init
git config user.email "test@example.com"
git config user.name "Test User"
# Add a dummy remote so the script doesn't fail
git remote add origin "file://$REMOTE_ROOT/dummy.git"
echo "Project root" > README.md
git add README.md
git commit -m "Initial project"

# Create repos.list mimicking the problem scenario
cat > repos.list <<EOF
file://$UPSTREAM_REPO@slides-2026-sta5069z slides
@data-2026-sta5069z data --worktree
file://$EVAL_REPO@2026-sta5069z eval
EOF

print_info "repos.list content:"
cat repos.list

# Run clone-repos.sh
OUTPUT=$("$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1 || true)
print_info "clone-repos.sh output:"
echo "$OUTPUT"

# Check 1: slides directory should exist
if [ -d "$WORK_DIR/slides/.git" ]; then
  print_pass "slides directory exists"
else
  print_fail "slides directory does not exist"
fi

# Check 2: data directory should exist (worktree)
if [ -e "$WORK_DIR/data/.git" ]; then
  print_pass "data directory exists"
else
  print_fail "data directory does not exist"
fi

# Check 3: data should be a worktree of slides, not a separate clone of lectures
if [ -d "$WORK_DIR/data/.git" ]; then
  # Check if data/.git is a file (indicates worktree)
  if [ -f "$WORK_DIR/data/.git" ]; then
    print_pass "data is a worktree (has .git file, not directory)"
    
    # Verify it points to slides, not lectures
    GITDIR=$(grep "gitdir:" "$WORK_DIR/data/.git" | cut -d' ' -f2)
    if echo "$GITDIR" | grep -q "slides"; then
      print_pass "data worktree is based on slides repository"
    else
      print_fail "data worktree is NOT based on slides repository: $GITDIR"
    fi
  else
    print_fail "data has .git directory (full clone), not worktree"
  fi
fi

# Check 4: lectures directory should NOT exist (no base clone)
if [ -d "$WORK_DIR/lectures" ]; then
  print_fail "lectures directory exists (should not - slides should be the base)"
else
  print_pass "lectures directory does not exist (correct)"
fi

# Check 5: Output should show branch existence message
if echo "$OUTPUT" | grep -q "Branch.*: data-2026-sta5069z"; then
  print_pass "Output shows branch existence/creation message for data-2026-sta5069z"
else
  print_fail "Output does not show branch existence/creation message"
  print_info "Expected to see 'Branch exists:' or 'Branch not found:' for data-2026-sta5069z"
fi

# Check 6: eval directory should exist
if [ -d "$WORK_DIR/eval/.git" ]; then
  print_pass "eval directory exists"
else
  print_fail "eval directory does not exist"
fi

# Check 7: Output should show branch existence message for eval
if echo "$OUTPUT" | grep -qE "(Branch.*: 2026-sta5069z|Remote branch.*2026-sta5069z)"; then
  print_pass "Output shows branch existence/creation message for 2026-sta5069z"
else
  print_fail "Output does not show branch existence/creation message for eval"
fi

# ============================================
# Test 2: Verify worktree branches are correct
# ============================================
print_test "Verify worktree branches are on correct branches"

if [ -d "$WORK_DIR/slides" ]; then
  SLIDES_BRANCH=$(cd "$WORK_DIR/slides" && git rev-parse --abbrev-ref HEAD)
  if [ "$SLIDES_BRANCH" = "slides-2026-sta5069z" ]; then
    print_pass "slides is on slides-2026-sta5069z branch"
  else
    print_fail "slides is on $SLIDES_BRANCH (expected slides-2026-sta5069z)"
  fi
fi

if [ -d "$WORK_DIR/data" ]; then
  DATA_BRANCH=$(cd "$WORK_DIR/data" && git rev-parse --abbrev-ref HEAD)
  if [ "$DATA_BRANCH" = "data-2026-sta5069z" ]; then
    print_pass "data is on data-2026-sta5069z branch"
  else
    print_fail "data is on $DATA_BRANCH (expected data-2026-sta5069z)"
  fi
fi

if [ -d "$WORK_DIR/eval" ]; then
  EVAL_BRANCH=$(cd "$WORK_DIR/eval" && git rev-parse --abbrev-ref HEAD)
  if [ "$EVAL_BRANCH" = "2026-sta5069z" ]; then
    print_pass "eval is on 2026-sta5069z branch"
  else
    print_fail "eval is on $EVAL_BRANCH (expected 2026-sta5069z)"
  fi
fi

# ============================================
# Test 3: Verify no errors in output
# ============================================
print_test "Verify no errors in clone-repos.sh output"

if echo "$OUTPUT" | grep -q "Errors.*: 0"; then
  print_pass "No errors reported in summary"
else
  ERROR_COUNT=$(echo "$OUTPUT" | grep "Errors" | grep -o "[0-9]\+")
  print_fail "Errors reported: $ERROR_COUNT"
fi

# ============================================
# Test 4: Global --worktree flag in repos.list
# ============================================
print_test "Global --worktree flag causes @branch lines to use worktrees"

WORK_DIR2="$TEST_ROOT/work2"
mkdir -p "$WORK_DIR2/sta5069z"
cd "$WORK_DIR2/sta5069z"

git init
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REMOTE_ROOT/dummy.git"
echo "Project root" > README.md
git add README.md
git commit -m "Initial project"

# Create repos.list with global --worktree flag (at the bottom, like the user's example)
cat > repos.list <<EOF
file://$UPSTREAM_REPO@slides-2026-sta5069z slides
@data-2026-sta5069z data
file://$EVAL_REPO@2026-sta5069z eval
--worktree
EOF

OUTPUT2=$("$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list --worktree 2>&1 || true)
print_info "clone-repos.sh output (global --worktree):"
echo "$OUTPUT2"

# Check that @data-2026-sta5069z was created as a worktree (not a separate clone)
if [ -e "$WORK_DIR2/data/.git" ]; then
  if [ -f "$WORK_DIR2/data/.git" ]; then
    print_pass "data is a worktree (global --worktree applied to @branch line)"
  else
    print_fail "data is a full clone, not a worktree (global --worktree not applied)"
  fi
else
  print_fail "data directory does not exist"
fi

# Check slides was cloned (not a worktree - it has a full repo spec)
if [ -d "$WORK_DIR2/slides/.git" ] && [ ! -f "$WORK_DIR2/slides/.git" ]; then
  print_pass "slides is a full clone (repo@branch lines unaffected by global --worktree)"
else
  print_fail "slides directory missing or is a worktree (unexpected)"
fi

# ============================================
# Test 5: Failed clone is reported as error
# ============================================
print_test "Failed clone is reported as an error, not silently ignored"

WORK_DIR3="$TEST_ROOT/work3"
mkdir -p "$WORK_DIR3/sta5069z"
cd "$WORK_DIR3/sta5069z"

git init
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REMOTE_ROOT/dummy.git"
echo "Project root" > README.md
git add README.md
git commit -m "Initial project"

# repos.list with a non-existent remote to trigger a clone failure
cat > repos.list <<EOF
file://$UPSTREAM_REPO@slides-2026-sta5069z slides
@data-2026-sta5069z data --worktree
file:///nonexistent/path/missing.git@some-branch missing
EOF

OUTPUT3=$("$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1 || true)
print_info "clone-repos.sh output (with failing clone):"
echo "$OUTPUT3"

# The failed clone must be counted as an error
if echo "$OUTPUT3" | grep -q "Errors.*: 1"; then
  print_pass "Failed clone is correctly counted as an error"
else
  print_fail "Failed clone not reported as error (expected Errors: 1)"
fi

# The summary must NOT show the failed clone as a successful clone
if echo "$OUTPUT3" | grep -q "Cloned (single-branch).*: 1"; then
  print_pass "Only the successful clone is counted in Cloned (single-branch)"
else
  # Both slides (successful) clone counts; the missing.git clone should NOT be counted
  CLONE_COUNT=$(echo "$OUTPUT3" | grep "Cloned (single-branch)" | grep -o "[0-9]\+")
  if [ "$CLONE_COUNT" -le 1 ]; then
    print_pass "Failed clone not counted in Cloned (single-branch): $CLONE_COUNT"
  else
    print_fail "Failed clone incorrectly counted in Cloned (single-branch): $CLONE_COUNT"
  fi
fi

# No spurious 'fatal: not a git repository' errors from post-clone operations
if echo "$OUTPUT3" | grep -q "fatal: not a git repository"; then
  print_fail "Spurious 'fatal: not a git repository' errors appeared (clone failure not handled early)"
else
  print_pass "No spurious 'fatal: not a git repository' errors after failed clone"
fi

# ============================================
# Summary
# ============================================
print_header "Test Summary"
echo "Tests run:    $TESTS_RUN"
echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"
else
  echo -e "${GREEN}Tests failed: $TESTS_FAILED${NC}"
fi

if [ $TESTS_FAILED -gt 0 ]; then
  exit 1
else
  exit 0
fi
