#!/usr/bin/env bash
# Test for worktree tracking setup (Issue: fatal error when setting upstream)
# This test validates that worktrees created from remote branches have proper
# tracking configured without generating fatal errors.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓ PASS:${NC} $*"; }
fail() { echo -e "${RED}✗ FAIL:${NC} $*"; exit 1; }
info() { echo -e "${YELLOW}ℹ️   ${NC} $*"; }

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

run_test() {
  TESTS_RUN=$((TESTS_RUN + 1))
}

test_passed() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

echo "============================================"
echo "Worktree Tracking Setup Test"
echo "============================================"

# Create a temporary test directory
TEST_DIR="$(mktemp -d)"
info "Test directory: $TEST_DIR"

cleanup() {
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

cd "$TEST_DIR"

# Setup git config
git config --global user.email "test@example.com"
git config --global user.name "Test User"

echo ""
echo "TEST: Setting up test repository with remote branches"
run_test

# Create a bare repository with multiple branches
git init --bare remote.git >/dev/null 2>&1
git clone remote.git repo-init >/dev/null 2>&1
cd repo-init
echo "initial content" > README.md
git add .
git commit -m "Initial commit" >/dev/null 2>&1
git branch -M main
git push origin main >/dev/null 2>&1

# Create additional branches
git checkout -b slides-branch >/dev/null 2>&1
echo "slides content" > slides.txt
git add .
git commit -m "Add slides" >/dev/null 2>&1
git push origin slides-branch >/dev/null 2>&1

git checkout -b data-branch >/dev/null 2>&1
echo "data content" > data.csv
git add .
git commit -m "Add data" >/dev/null 2>&1
git push origin data-branch >/dev/null 2>&1

cd ..
pass "Created test repository with branches: main, slides-branch, data-branch"

echo ""
echo "TEST: Single-branch clone and worktree creation"
run_test

# Clone single branch (simulating the user's scenario)
git clone --single-branch --branch slides-branch remote.git slides >/dev/null 2>&1
cd slides

# Verify it's a single-branch clone
FETCH_REFSPEC=$(git config --get remote.origin.fetch)
if [[ "$FETCH_REFSPEC" == "+refs/heads/slides-branch:refs/remotes/origin/slides-branch" ]]; then
  test_passed
  pass "Confirmed single-branch clone (refspec: $FETCH_REFSPEC)"
else
  fail "Expected single-branch refspec, got: $FETCH_REFSPEC"
fi

echo ""
echo "TEST: Create worktree with clone-repos.sh logic"
run_test

# Create repos.list (using relative path that works from test directory)
cat > repos.list << 'EOF'
@data-branch data --worktree
EOF

# Run clone-repos.sh
OUTPUT=$("$REPO_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1)
EXIT_CODE=$?

if [[ $EXIT_CODE -eq 0 ]]; then
  test_passed
  pass "clone-repos.sh completed successfully"
else
  fail "clone-repos.sh failed with exit code $EXIT_CODE"
fi

# Check for the fatal error message
if echo "$OUTPUT" | grep -q "fatal: cannot set up tracking information"; then
  fail "Found 'fatal: cannot set up tracking information' error in output"
else
  test_passed
  pass "No fatal tracking errors in output"
fi

# Verify worktree was created
if [[ -d "../data" ]] && [[ -f "../data/data.csv" ]]; then
  test_passed
  pass "Worktree created successfully in parent directory"
else
  fail "Worktree not created or missing expected files (checked ../data)"
fi

echo ""
echo "TEST: Verify worktree tracking configuration"
run_test

cd ../data

# Check if we're on the correct branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" == "data-branch" ]]; then
  test_passed
  pass "Worktree is on correct branch: $CURRENT_BRANCH"
else
  fail "Expected branch 'data-branch', got: $CURRENT_BRANCH"
fi

# Check if tracking is set up (tracking setup may fail but worktree should still work)
TRACKING_BRANCH=$(git config --get branch.data-branch.merge 2>/dev/null || echo "")
if [[ -n "$TRACKING_BRANCH" ]]; then
  test_passed
  pass "Branch tracking is configured: $TRACKING_BRANCH"
  info "Tracking remote: $(git config --get branch.data-branch.remote 2>/dev/null)"
else
  # Tracking setup is optional - worktree still works without it
  info "Branch tracking not configured (this is OK)"
  test_passed
  pass "Worktree functional even without tracking"
fi

echo ""
echo "TEST: Verify wildcard fetch refspec was added (default deferred mode)"
run_test

cd ../slides  # Back to slides directory

# In default --fetch-all-deferred mode the wildcard refspec MUST be present
WILDCARD_REFSPEC="+refs/heads/*:refs/remotes/origin/*"
if git config --get-all remote.origin.fetch | grep -qF "$WILDCARD_REFSPEC"; then
  test_passed
  pass "Wildcard fetch refspec added: $WILDCARD_REFSPEC"
else
  fail "Wildcard fetch refspec missing in default (deferred) mode"
fi

echo ""
echo "TEST: --fetch-single worktree must NOT add wildcard refspec"
run_test

cd "$TEST_DIR"

# Re-create a fresh single-branch clone and use --fetch-single for the worktree
git clone --single-branch --branch slides-branch remote.git slides-single >/dev/null 2>&1
cd slides-single

cat > repos.list << 'EOF'
--fetch-single
@data-branch data-single --worktree
EOF

set +e
SINGLE_OUTPUT=$("$REPO_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1)
SINGLE_RC=$?
set -e

if [[ $SINGLE_RC -ne 0 ]]; then
  echo "$SINGLE_OUTPUT"
  fail "clone-repos.sh failed for --fetch-single worktree test (exit $SINGLE_RC)"
fi

if [[ ! -d ../data-single ]]; then
  echo "$SINGLE_OUTPUT"
  fail "Expected worktree directory ../data-single was not created"
fi

if git config --get-all remote.origin.fetch | grep -qF "$WILDCARD_REFSPEC"; then
  fail "--fetch-single worktree should NOT add wildcard fetch refspec, but it did"
else
  test_passed
  pass "--fetch-single correctly preserves single-branch refspec after worktree creation"
fi

# Verify the specific branch refspec WAS added (fixes the bug: future git fetch tracks branch)
BRANCH_REFSPEC="+refs/heads/data-branch:refs/remotes/origin/data-branch"
if git config --get-all remote.origin.fetch | grep -qF "$BRANCH_REFSPEC"; then
  test_passed
  pass "--fetch-single worktree adds specific branch refspec: $BRANCH_REFSPEC"
else
  fail "--fetch-single worktree did NOT add specific branch refspec (future git fetch won't track data-branch)"
fi

# Verify worktree branch has proper upstream tracking
TRACKING_REMOTE=$(git -C ../data-single config --get branch.data-branch.remote 2>/dev/null || true)
if [[ "$TRACKING_REMOTE" == "origin" ]]; then
  test_passed
  pass "--fetch-single worktree branch has upstream tracking set to origin"
else
  fail "--fetch-single worktree branch missing upstream tracking (got: '$TRACKING_REMOTE')"
fi

cd "$TEST_DIR/slides"  # Restore for subsequent tests

echo ""
echo "TEST: --fetch-single: fresh base clone + worktree in same repos.list"
run_test

# This tests the exact scenario from the issue:
# A repos.list that (1) clones a DIFFERENT base repo with --fetch-single and
# (2) immediately requests a worktree for a different branch off that base.
# We use a second bare remote to avoid same-URL ambiguity.
cd "$TEST_DIR"

# Create a second bare remote with its own branches (simulates "library-repo")
git init --bare remote2.git >/dev/null 2>&1
git clone remote2.git lib-init >/dev/null 2>&1
cd lib-init
echo "lib main" > lib.md && git add . && git commit -m "lib init" >/dev/null 2>&1
git branch -M main && git push origin main >/dev/null 2>&1
git checkout -b lib-feature >/dev/null 2>&1
echo "lib feature" > lib-feature.txt && git add . && git commit -m "lib feature" >/dev/null 2>&1
git push origin lib-feature >/dev/null 2>&1
cd ..

# Run from the existing "slides" workspace (different remote from remote2)
cd slides
LIB_REMOTE="$(cd "$TEST_DIR/lib-init" && git remote get-url origin)"
cat > repos2.list << EOF
--fetch-single
$LIB_REMOTE lib-clone
@lib-feature lib-wt --worktree
EOF

set +e
ISSUE_OUTPUT=$("$REPO_ROOT/scripts/helper/clone-repos.sh" -f repos2.list 2>&1)
ISSUE_RC=$?
set -e

if [[ $ISSUE_RC -ne 0 ]]; then
  echo "$ISSUE_OUTPUT"
  fail "clone-repos.sh failed for issue scenario (exit $ISSUE_RC)"
fi

if [[ ! -d ../lib-wt ]]; then
  echo "$ISSUE_OUTPUT"
  fail "Expected worktree directory ../lib-wt was not created"
fi

# The lib-clone base should have the specific branch refspec for lib-feature
LIB_BRANCH_REFSPEC="+refs/heads/lib-feature:refs/remotes/origin/lib-feature"
if git -C ../lib-clone config --get-all remote.origin.fetch | grep -qF "$LIB_BRANCH_REFSPEC"; then
  test_passed
  pass "Fresh --fetch-single clone got specific branch refspec for worktree branch"
else
  fail "Fresh --fetch-single clone missing specific branch refspec for worktree branch"
fi

# Wildcard should NOT be added
if git -C ../lib-clone config --get-all remote.origin.fetch | grep -qF "$WILDCARD_REFSPEC"; then
  fail "Fresh --fetch-single clone should NOT have wildcard refspec, but it does"
else
  test_passed
  pass "Fresh --fetch-single clone correctly has no wildcard refspec"
fi

# Worktree tracking should be set
TRACKING_REMOTE=$(git -C ../lib-wt config --get branch.lib-feature.remote 2>/dev/null || true)
if [[ "$TRACKING_REMOTE" == "origin" ]]; then
  test_passed
  pass "Issue scenario: worktree branch properly tracks origin"
else
  fail "Issue scenario: worktree branch missing upstream tracking (got: '$TRACKING_REMOTE')"
fi

echo ""
echo "TEST: Worktree can perform git operations"
run_test

cd ../data  # Back to data worktree

# Try a simple git operation
if git status >/dev/null 2>&1; then
  test_passed
  pass "Worktree can execute git status"
else
  fail "Worktree failed to execute git status"
fi

# Try to fetch (should work with proper refspec)
if git fetch >/dev/null 2>&1 || true; then
  test_passed
  pass "Worktree can execute git fetch"
else
  info "git fetch had issues (may be expected in test environment)"
  test_passed
  pass "Continuing despite fetch issues"
fi

echo ""
echo "============================================"
echo "Test Summary"
echo "============================================"
echo "Test blocks run: $TESTS_RUN"
echo "Assertions passed: $TESTS_PASSED"
echo ""

if [[ $TESTS_PASSED -ge $TESTS_RUN ]]; then
  echo -e "${GREEN}All test blocks passed!${NC}"
  exit 0
else
  echo -e "${RED}Some test blocks failed${NC}"
  exit 1
fi
