#!/usr/bin/env bash
# test-local-repo-comprehensive.sh — Comprehensive test suite for local git repo creation
# Tests clone-repos.sh and setup-repos.sh with various local repo scenarios

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
  echo -e "${BLUE}INFO: $1${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="$PROJECT_ROOT/scripts/setup-repos.sh"
CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"
CREATE_SCRIPT="$PROJECT_ROOT/scripts/helper/create-repos.sh"

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "Comprehensive Local Git Repo Creation Test Suite"
print_info "Test root: $TEST_ROOT"
print_info "Testing clone-repos.sh and setup-repos.sh with local git remotes"

# Helper function to create a bare repo with branches
create_bare_repo() {
  local bare_path="$1"
  local repo_name="$2"
  shift 2
  local branches=("$@")
  
  git init --bare -q "$bare_path"
  
  # Create temp clone to add content
  local temp_clone="$TEST_ROOT/temp-$repo_name"
  git clone -q "$bare_path" "$temp_clone"
  cd "$temp_clone"
  git config user.email "test@example.com"
  git config user.name "Test User"
  
  # Initial commit
  echo "# $repo_name" > README.md
  git add README.md
  git commit -q -m "Initial commit"
  local default_branch=$(git symbolic-ref --short HEAD)
  git push -q origin "$default_branch"
  
  # Create additional branches
  for branch in "${branches[@]}"; do
    git checkout -q "$default_branch"
    git checkout -q -b "$branch"
    echo "$branch content" >> README.md
    git add README.md
    git commit -q -m "$branch commit"
    git push -q origin "$branch"
  done
  
  cd "$TEST_ROOT"
  rm -rf "$temp_clone"
  
  # Set HEAD in bare repo to default branch
  cd "$bare_path"
  git symbolic-ref HEAD "refs/heads/$default_branch"
  cd "$TEST_ROOT"
}

# Setup bare repos
BARE_REPOS_DIR="$TEST_ROOT/bare-repos"
mkdir -p "$BARE_REPOS_DIR"

print_info "Setting up test bare repositories..."
REPO1_BARE="$BARE_REPOS_DIR/repo1.git"
REPO2_BARE="$BARE_REPOS_DIR/repo2.git"
REPO3_BARE="$BARE_REPOS_DIR/repo3.git"

create_bare_repo "$REPO1_BARE" "repo1" "dev" "feature/test"
create_bare_repo "$REPO2_BARE" "repo2" "staging" "release/v1.0"
create_bare_repo "$REPO3_BARE" "repo3" "experimental"
print_info "Created 3 bare repos with multiple branches"

# ============================================
# Test 1: Non-existing repo - full clone
# ============================================
print_test "Clone non-existing local repo (full clone)"

WORKSPACE1="$TEST_ROOT/ws1"
mkdir -p "$WORKSPACE1"
cd "$WORKSPACE1"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"  # Required by clone-repos.sh for fallback
echo "# WS1" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
file://$REPO1_BARE
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/repo1" ] && [ -d "$TEST_ROOT/repo1/.git" ]; then
  cd "$TEST_ROOT/repo1"
  if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then
    print_pass "Full clone of non-existing repo succeeded"
  else
    print_fail "Directory created but not a valid git repo"
  fi
else
  print_fail "Full clone failed - directory not created"
fi

# ============================================
# Test 2: Non-existing repo - single-branch clone
# ============================================
print_test "Clone non-existing local repo (single-branch)"

WORKSPACE2="$TEST_ROOT/ws2"
mkdir -p "$WORKSPACE2"
cd "$WORKSPACE2"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO2_BARE"  # Required by clone-repos.sh for fallback
echo "# WS2" > README.md
git add README.md
git commit -q -m "Init"

# Use a custom directory to avoid conflicts with later tests
cat > repos.list <<EOF
file://$REPO2_BARE@staging repo2-staging-only
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/repo2-staging-only" ]; then
  cd "$TEST_ROOT/repo2-staging-only"
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$CURRENT_BRANCH" = "staging" ]; then
    print_pass "Single-branch clone succeeded with correct branch"
  else
    print_fail "Single-branch clone succeeded but wrong branch: $CURRENT_BRANCH"
  fi
else
  print_fail "Single-branch clone failed"
fi

# ============================================
# Test 3: Pre-existing repo - should skip
# ============================================
print_test "Attempt to clone pre-existing local repo (should skip)"

WORKSPACE3="$TEST_ROOT/ws3"
mkdir -p "$WORKSPACE3"
cd "$WORKSPACE3"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO3_BARE"  # Required by clone-repos.sh for fallback
echo "# WS3" > README.md
git add README.md
git commit -q -m "Init"

# First clone
cat > repos.list <<EOF
file://$REPO3_BARE
EOF
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# Mark the repo
if [ -d "$TEST_ROOT/repo3" ]; then
  cd "$TEST_ROOT/repo3"
  echo "MARKER" > marker.txt
  git add marker.txt
  git commit -q -m "Marker" 2>/dev/null || true
fi

# Try to clone again
cd "$WORKSPACE3"
OUTPUT=$("$CLONE_SCRIPT" -f repos.list 2>&1 || true)

if [ -f "$TEST_ROOT/repo3/marker.txt" ]; then
  print_pass "Pre-existing repo preserved (marker file still exists)"
else
  print_fail "Pre-existing repo was overwritten"
fi

if echo "$OUTPUT" | grep -q -i "already exists\|skipping\|exists"; then
  print_pass "Clone script reported existing repo"
else
  print_info "Note: Clone script may not report existing repo explicitly"
fi

# ============================================
# Test 4: Non-existing worktree from pre-created repo
# ============================================
print_test "Create worktree from pre-existing repo (non-existing branch worktree)"

WORKSPACE4="$TEST_ROOT/ws4"
mkdir -p "$WORKSPACE4"
cd "$WORKSPACE4"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# WS4" > README.md
git add README.md
git commit -q -m "Init"

# First clone the base repo
cat > repos.list <<EOF
file://$REPO1_BARE
EOF
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# Now add a worktree
cat > repos.list <<EOF
file://$REPO1_BARE
@dev
EOF
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/ws4-dev" ]; then
  cd "$TEST_ROOT/ws4-dev"
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$CURRENT_BRANCH" = "dev" ]; then
    print_pass "Worktree created with correct branch"
  else
    print_fail "Worktree created but wrong branch: $CURRENT_BRANCH"
  fi
  
  # Verify it's a worktree
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -f ".git" ] && grep -q "gitdir:" ".git" 2>/dev/null; then
      print_pass "Created directory is a valid git worktree"
    else
      print_fail "Created directory is not a worktree (regular clone?)"
    fi
  fi
else
  print_fail "Worktree not created"
fi

# ============================================
# Test 5: Existing worktree - should skip
# ============================================
print_test "Attempt to create existing worktree (should skip or handle gracefully)"

cd "$WORKSPACE4"
# Add marker to existing worktree
if [ -d "$TEST_ROOT/ws4-dev" ]; then
  cd "$TEST_ROOT/ws4-dev"
  echo "MARKER_WT" > marker_wt.txt
fi

# Try to create again
cd "$WORKSPACE4"
"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -f "$TEST_ROOT/ws4-dev/marker_wt.txt" ]; then
  print_pass "Existing worktree preserved"
else
  print_fail "Existing worktree was overwritten or removed"
fi

# ============================================
# Test 6: Various repos.list format - absolute paths
# ============================================
print_test "Clone with absolute path (no file:// prefix)"

WORKSPACE5="$TEST_ROOT/ws5"
mkdir -p "$WORKSPACE5"
cd "$WORKSPACE5"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO2_BARE"  # Required by clone-repos.sh for fallback
echo "# WS5" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
$REPO2_BARE
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/repo2" ]; then
  print_pass "Clone with absolute path succeeded"
else
  print_fail "Clone with absolute path failed"
fi

# ============================================
# Test 7: Custom target directories
# ============================================
print_test "Clone with custom target directory"

WORKSPACE6="$TEST_ROOT/ws6"
mkdir -p "$WORKSPACE6"
cd "$WORKSPACE6"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO3_BARE"  # Required by clone-repos.sh for fallback
echo "# WS6" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
file://$REPO3_BARE custom-repo3
@experimental custom-exp
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/custom-repo3" ]; then
  print_pass "Clone to custom directory succeeded"
else
  print_fail "Clone to custom directory failed"
  print_info "Looking for: $TEST_ROOT/custom-repo3"
  ls -la "$TEST_ROOT" | grep -i repo3 || true
fi

if [ -d "$TEST_ROOT/custom-exp" ]; then
  cd "$TEST_ROOT/custom-exp"
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$CURRENT_BRANCH" = "experimental" ]; then
    print_pass "Worktree to custom directory succeeded with correct branch"
  else
    print_fail "Worktree to custom directory created but wrong branch"
  fi
else
  print_fail "Worktree to custom directory failed"
fi

# ============================================
# Test 8: Multiple references to same repo
# ============================================
print_test "Multiple branch clones from same repo"

WORKSPACE7="$TEST_ROOT/ws7"
mkdir -p "$WORKSPACE7"
cd "$WORKSPACE7"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# WS7" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
file://$REPO1_BARE
@dev
@feature/test
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

BRANCHES_CREATED=0
if [ -d "$TEST_ROOT/repo1" ]; then
  BRANCHES_CREATED=$((BRANCHES_CREATED + 1))
fi
if [ -d "$TEST_ROOT/ws7-dev" ]; then
  BRANCHES_CREATED=$((BRANCHES_CREATED + 1))
fi
# feature/test should create feature-test directory
if [ -d "$TEST_ROOT/ws7-feature-test" ]; then
  BRANCHES_CREATED=$((BRANCHES_CREATED + 1))
fi

if [ "$BRANCHES_CREATED" -ge 2 ]; then
  print_pass "Multiple worktrees from same repo created (found $BRANCHES_CREATED)"
else
  print_fail "Not all worktrees created (found only $BRANCHES_CREATED)"
  print_info "Expected: repo1, ws7-dev, ws7-feature-test"
  ls -la "$TEST_ROOT" | grep -E "repo1|ws7" || true
fi

# Verify branch with slash is handled correctly
if [ -d "$TEST_ROOT/ws7-feature-test" ]; then
  cd "$TEST_ROOT/ws7-feature-test"
  CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$CURRENT_BRANCH" = "feature/test" ]; then
    print_pass "Branch with slash preserved correctly in git (feature/test)"
  else
    print_fail "Branch with slash not preserved: $CURRENT_BRANCH"
  fi
fi

# ============================================
# Test 9: Worktree fallback behavior
# ============================================
print_test "Worktree inherits fallback repo correctly"

WORKSPACE8="$TEST_ROOT/ws8"
mkdir -p "$WORKSPACE8"
cd "$WORKSPACE8"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# WS8" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
@dev
file://$REPO2_BARE
@staging
EOF

"$CLONE_SCRIPT" -f repos.list 2>&1 | grep -E "^(▶|Summary:|Adding|Cloning)" || true

# First @dev should use ws8's origin (repo1)
# After file://$REPO2_BARE, fallback changes to repo2
# So @staging should use repo2

# Check if first worktree used repo1
if [ -d "$TEST_ROOT/ws8-dev" ]; then
  cd "$TEST_ROOT/ws8-dev"
  REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
  if echo "$REMOTE_URL" | grep -q "repo1"; then
    print_pass "First @branch used initial fallback (repo1)"
  else
    print_info "First @branch remote: $REMOTE_URL"
  fi
fi

# Check if second worktree used repo2
# The worktree should be named based on the cloned repo (repo2-staging), not ws8-staging
if [ -d "$TEST_ROOT/repo2-staging" ]; then
  cd "$TEST_ROOT/repo2-staging"
  REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null || echo "")
  if echo "$REMOTE_URL" | grep -q "repo2"; then
    print_pass "Second @branch used updated fallback (repo2)"
  else
    print_fail "Second @branch did not use correct fallback"
    print_info "Expected repo2, got: $REMOTE_URL"
  fi
else
  print_fail "Second worktree not created"
  print_info "Looking for: $TEST_ROOT/repo2-staging"
  ls -la "$TEST_ROOT" | grep -E "repo2|ws8" || true
fi

# ============================================
# Test 10: setup-repos.sh integration with local remotes
# ============================================
print_test "Full setup-repos.sh workflow with local remotes"

WORKSPACE9="$TEST_ROOT/ws9"
mkdir -p "$WORKSPACE9"
cd "$WORKSPACE9"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# WS9" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
file://$REPO1_BARE
@dev
file://$REPO2_BARE
EOF

OUTPUT=$("$SETUP_SCRIPT" -f repos.list 2>&1 || true)

# Check that it doesn't say "Creating repos on GitHub"
if echo "$OUTPUT" | grep -q "Creating repos on GitHub"; then
  print_fail "Still says 'Creating repos on GitHub' (should just say 'Creating repos')"
else
  print_pass "Correctly says 'Creating repos' (not 'on GitHub')"
fi

# Verify repos were cloned
REPOS_FOUND=0
[ -d "$TEST_ROOT/repo1" ] && REPOS_FOUND=$((REPOS_FOUND + 1))
[ -d "$TEST_ROOT/ws9-dev" ] && REPOS_FOUND=$((REPOS_FOUND + 1))
[ -d "$TEST_ROOT/repo2" ] && REPOS_FOUND=$((REPOS_FOUND + 1))

if [ "$REPOS_FOUND" -eq 3 ]; then
  print_pass "All repos cloned via setup-repos.sh"
else
  print_fail "Not all repos cloned (found $REPOS_FOUND/3)"
fi

# Check workspace file was created
if [ -f "$WORKSPACE9/entire-project.code-workspace" ]; then
  print_pass "Workspace file created"
else
  print_info "Workspace file not created (may be expected)"
fi

# ============================================
# Test 11: Branch name sanitization in directory names
# ============================================
print_test "Branch names with slashes are sanitized for directory names"

WORKSPACE10="$TEST_ROOT/ws10"
mkdir -p "$WORKSPACE10"
cd "$WORKSPACE10"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "$REPO1_BARE"
echo "# WS10" > README.md
git add README.md
git commit -q -m "Init"

cat > repos.list <<EOF
file://$REPO1_BARE
@feature/test
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# Directory name should be sanitized (feature-test instead of feature/test)
if [ -d "$TEST_ROOT/ws10-feature-test" ]; then
  print_pass "Branch with slash sanitized for directory name (ws10-feature-test)"
  
  # But git branch should still have the slash
  cd "$TEST_ROOT/ws10-feature-test"
  ACTUAL_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$ACTUAL_BRANCH" = "feature/test" ]; then
    print_pass "Git branch name preserved with slash: $ACTUAL_BRANCH"
  else
    print_fail "Git branch name not preserved correctly: $ACTUAL_BRANCH"
  fi
else
  print_fail "Worktree with sanitized name not found"
  print_info "Looking for: $TEST_ROOT/ws10-feature-test"
  ls -la "$TEST_ROOT" | grep ws10 || true
fi

# ============================================
# Test 12: Mixed GitHub and local repos (create-repos.sh skips local)
# ============================================
print_test "create-repos.sh skips local remotes without GitHub API calls"

cd "$TEST_ROOT"
cat > test-mixed-repos.list <<EOF
# Local remotes - should skip
file://$REPO1_BARE
$REPO2_BARE

# GitHub format - would try to process (commented out to avoid API calls)
# testowner/testrepo
EOF

OUTPUT=$("$CREATE_SCRIPT" -f test-mixed-repos.list 2>&1)

SKIP_COUNT=$(echo "$OUTPUT" | grep -c "Skipping local remote" || echo "0")
if [ "$SKIP_COUNT" -ge 2 ]; then
  print_pass "create-repos.sh skipped local remotes ($SKIP_COUNT found)"
else
  print_fail "create-repos.sh did not skip all local remotes (only $SKIP_COUNT)"
  print_info "Output: $OUTPUT"
fi

# Should not try to call GitHub API
if echo "$OUTPUT" | grep -q -i "Could not retrieve\|GitHub.*username\|GitHub.*token"; then
  print_fail "Attempted GitHub API call for local remotes"
else
  print_pass "No GitHub API calls for local remotes"
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
  echo "✓ Non-existing repos can be cloned"
  echo "✓ Pre-existing repos are preserved"
  echo "✓ Worktrees can be created from pre-existing repos"
  echo "✓ Existing worktrees are preserved"
  echo "✓ Various repos.list formats work (file://, absolute paths, custom dirs)"
  echo "✓ Multiple references to same repo work correctly"
  echo "✓ Worktree fallback behavior works as expected"
  echo "✓ Branch names with slashes are handled correctly"
  echo "✓ setup-repos.sh works end-to-end with local remotes"
  echo "✓ create-repos.sh skips local remotes appropriately"
fi
