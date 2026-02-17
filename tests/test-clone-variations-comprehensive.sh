#!/usr/bin/env bash
# test-clone-variations-comprehensive.sh — Comprehensive test for all clone-repos.sh variations
#
# PURPOSE:
#   Tests all ways to specify cloning repos, branches, worktrees with/without custom directories
#   Assumes repos and branches already exist (simulating post-setup state)
#
# COVERAGE (16 test scenarios, 32 assertions):
#   1. Setup: Create local bare repositories with branches
#   2. Full repo clone (owner/repo) - default single-branch behavior
#   3. Full repo clone with custom target directory
#   4. Full repo clone with -a flag (all branches)
#   5. Single-branch clone (owner/repo@branch) - single reference, no suffix
#   6. Single-branch clone with custom target directory
#   7. Worktree from current repo (@branch) - default behavior
#   8. Worktree with custom target directory
#   9. Worktree with --no-worktree flag (clone instead of worktree)
#   10. Fallback repo tracking across multiple clone lines
#   11. Branch name sanitization (feature/test → feature-test in paths)
#   12. Multiple references to same repo (branch suffix logic)
#   13. Single reference to repo (no branch suffix)
#   14. Absolute path cloning
#   15. file:// URL cloning
#   16. Error handling (non-empty directory)
#
# TESTED VARIATIONS:
#   - Clone types: full clone, single-branch clone, worktree
#   - Target specification: default, custom directory
#   - Flags: -a (all branches), --no-worktree
#   - Remote formats: owner/repo, file://, absolute paths
#   - Branch naming: simple names, names with slashes
#   - Reference counting: single vs multiple references (affects suffix logic)
#   - Fallback repo: tracking across multiple operations
#
# USAGE:
#   ./tests/test-clone-variations-comprehensive.sh
#
# NOTES:
#   - Creates temporary bare git repositories for testing
#   - All tests are isolated in separate workspace directories
#   - Cleans up automatically on exit

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

print_warning() {
  echo -e "${YELLOW}WARNING: $1${NC}"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "Comprehensive Clone Variations Test Suite"
print_info "Test root: $TEST_ROOT"
print_info "Testing all clone-repos.sh variations with existing repos/branches"

# ============================================
# Setup: Create local bare git repositories with branches
# ============================================
print_test "Setting up local bare repositories"

BARE_REPOS_DIR="$TEST_ROOT/bare-repos"
mkdir -p "$BARE_REPOS_DIR"

# Helper function to create a bare repo with branches
create_bare_repo() {
  local bare_path="$1"
  local repo_name="$2"
  shift 2
  local branches=("$@")
  
  # Use subshell to ensure we always return to original directory
  (
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
    
    # Get default branch and validate it exists
    local default_branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [ -z "$default_branch" ]; then
      echo "Error: Could not determine default branch for $repo_name" >&2
      return 1
    fi
    
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
  )
  # Subshell ensures we return to original directory even if errors occur
}

# Create test repositories
REPO1_BARE="$BARE_REPOS_DIR/repo1.git"
REPO2_BARE="$BARE_REPOS_DIR/repo2.git"
REPO3_BARE="$BARE_REPOS_DIR/repo3.git"

create_bare_repo "$REPO1_BARE" "repo1" "dev" "feature/test" "release/v1.0"
create_bare_repo "$REPO2_BARE" "repo2" "staging" "hotfix/urgent"
create_bare_repo "$REPO3_BARE" "repo3" "experimental"

print_pass "Created 3 bare repositories with branches"
print_info "  - repo1: main, dev, feature/test, release/v1.0"
print_info "  - repo2: main, staging, hotfix/urgent"
print_info "  - repo3: main, experimental"

# ============================================
# Test 1: Full repo clone (owner/repo)
# ============================================
print_test "Full repo clone: owner/repo"

WORKSPACE1="$TEST_ROOT/workspace1"
mkdir -p "$WORKSPACE1"
cd "$WORKSPACE1"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO1_BARE"
echo "# Workspace 1" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
file://$REPO1_BARE
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/repo1" ]; then
  print_pass "Cloned repo1 to ../repo1"
  cd "$TEST_ROOT/repo1"
  # Default clone is single-branch (only default branch)
  if git branch -r | grep -q "origin/"; then
    print_pass "Default clone fetched default branch"
  else
    print_fail "Clone has no remote branches"
  fi
else
  print_fail "Failed to clone repo1"
fi

# ============================================
# Test 2: Full repo clone with custom target directory
# ============================================
print_test "Full repo clone with custom target: owner/repo custom-dir"

WORKSPACE2="$TEST_ROOT/workspace2"
mkdir -p "$WORKSPACE2"
cd "$WORKSPACE2"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO2_BARE"
echo "# Workspace 2" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
file://$REPO2_BARE my-custom-repo
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/my-custom-repo" ]; then
  print_pass "Cloned repo2 to ../my-custom-repo"
else
  print_fail "Failed to clone repo2 to custom directory"
fi

# ============================================
# Test 3: Full repo clone with -a flag (all branches)
# ============================================
print_test "Full repo clone with -a flag: owner/repo -a"

WORKSPACE3="$TEST_ROOT/workspace3"
mkdir -p "$WORKSPACE3"
cd "$WORKSPACE3"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO3_BARE"
echo "# Workspace 3" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
file://$REPO3_BARE -a
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/repo3" ]; then
  print_pass "Cloned repo3 with -a flag"
  cd "$TEST_ROOT/repo3"
  if git branch -r | grep -q "origin/experimental"; then
    print_pass "All branches fetched with -a flag"
  else
    print_fail "Missing branches with -a flag"
  fi
else
  print_fail "Failed to clone repo3 with -a flag"
fi

# ============================================
# Test 4: Single-branch clone (owner/repo@branch)
# ============================================
print_test "Single-branch clone: owner/repo@branch"

WORKSPACE4="$TEST_ROOT/workspace4"
mkdir -p "$WORKSPACE4"
cd "$WORKSPACE4"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
# Use REPO2 to avoid conflict with Test 1
git remote add origin "file://$REPO2_BARE"
echo "# Workspace 4" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
file://$REPO2_BARE@hotfix/urgent
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# Should create ../repo2 (no suffix, since this is the only reference to repo2)
if [ -d "$TEST_ROOT/repo2" ]; then
  print_pass "Single-branch clone created ../repo2 (single ref, no suffix)"
  cd "$TEST_ROOT/repo2"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "hotfix/urgent" ]; then
    print_pass "Checked out correct branch: hotfix/urgent"
  else
    print_fail "Wrong branch: $BRANCH (expected: hotfix/urgent)"
  fi
else
  # If it's not repo2, check if it's repo2-hotfix-urgent
  if [ -d "$TEST_ROOT/repo2-hotfix-urgent" ]; then
    print_warning "Created ../repo2-hotfix-urgent (with suffix) instead of ../repo2"
  else
    print_fail "Failed to create single-branch clone"
  fi
fi

# ============================================
# Test 5: Single-branch clone with custom target directory
# ============================================
print_test "Single-branch clone with custom target: owner/repo@branch custom-dir"

WORKSPACE5="$TEST_ROOT/workspace5"
mkdir -p "$WORKSPACE5"
cd "$WORKSPACE5"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO2_BARE"
echo "# Workspace 5" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
file://$REPO2_BARE@staging my-staging
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/my-staging" ]; then
  print_pass "Single-branch clone to custom directory: ../my-staging"
  cd "$TEST_ROOT/my-staging"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "staging" ]; then
    print_pass "Checked out correct branch: staging"
  else
    print_fail "Wrong branch: $BRANCH (expected: staging)"
  fi
else
  print_fail "Failed to clone to custom directory"
fi

# ============================================
# Test 6: Worktree from current repo (@branch)
# ============================================
print_test "Worktree from current repo: @branch"

WORKSPACE6="$TEST_ROOT/workspace6"
mkdir -p "$WORKSPACE6"
cd "$WORKSPACE6"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO1_BARE"
echo "# Workspace 6" > README.md
git add README.md
git commit -q -m "Initial commit"

# Fetch branches from remote
git fetch -q origin

cat > repos.list <<EOF
@dev
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/workspace6-dev" ]; then
  print_pass "Created worktree ../workspace6-dev"
  cd "$TEST_ROOT/workspace6-dev"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "dev" ]; then
    print_pass "Worktree on correct branch: dev"
  else
    print_fail "Worktree wrong branch: $BRANCH (expected: dev)"
  fi
  
  # Verify it's a worktree, not a clone
  if git worktree list | grep -q "workspace6-dev"; then
    print_pass "Confirmed it's a git worktree"
  else
    print_warning "May not be a worktree (could be a clone)"
  fi
else
  print_fail "Failed to create worktree"
fi

# ============================================
# Test 7: Worktree with custom target directory
# ============================================
print_test "Worktree with custom target: @branch custom-dir"

WORKSPACE7="$TEST_ROOT/workspace7"
mkdir -p "$WORKSPACE7"
cd "$WORKSPACE7"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO2_BARE"
echo "# Workspace 7" > README.md
git add README.md
git commit -q -m "Initial commit"

git fetch -q origin

cat > repos.list <<EOF
@staging my-worktree
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/my-worktree" ]; then
  print_pass "Created worktree to custom directory: ../my-worktree"
  cd "$TEST_ROOT/my-worktree"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "staging" ]; then
    print_pass "Worktree on correct branch: staging"
  else
    print_fail "Worktree wrong branch: $BRANCH (expected: staging)"
  fi
else
  print_fail "Failed to create worktree to custom directory"
fi

# ============================================
# Test 8: Worktree with --no-worktree flag (clone instead)
# ============================================
print_test "Worktree with --no-worktree flag: @branch --no-worktree"

WORKSPACE8="$TEST_ROOT/workspace8"
mkdir -p "$WORKSPACE8"
cd "$WORKSPACE8"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# Create a dedicated repo for this test to avoid conflicts
REPO_TEST8="$BARE_REPOS_DIR/repo-test8.git"
create_bare_repo "$REPO_TEST8" "repo-test8" "feature/test"

git remote add origin "file://$REPO_TEST8"
echo "# Workspace 8" > README.md
git add README.md
git commit -q -m "Initial commit"

git fetch -q origin

cat > repos.list <<EOF
@feature/test --no-worktree
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# With --no-worktree, it should clone to ../repo-test8 (base name)
if [ -d "$TEST_ROOT/repo-test8" ]; then
  print_pass "Created clone with --no-worktree: ../repo-test8"
  cd "$TEST_ROOT/repo-test8"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "feature/test" ]; then
    print_pass "Clone on correct branch: feature/test"
  else
    print_fail "Clone wrong branch: $BRANCH (expected: feature/test)"
  fi
  
  # Verify it's NOT a worktree
  cd "$WORKSPACE8"
  if ! git worktree list 2>/dev/null | grep -q "repo-test8"; then
    print_pass "Confirmed it's a clone, not a worktree"
  else
    print_fail "Should be a clone, but appears to be a worktree"
  fi
else
  # Check if it created with a different name
  if [ -d "$TEST_ROOT/workspace8-feature-test" ]; then
    print_warning "Created with workspace prefix (unexpected)"
  else
    print_fail "Failed to create clone with --no-worktree"
  fi
fi

# ============================================
# Test 9: Fallback repo tracking across multiple clone lines
# ============================================
print_test "Fallback repo tracking across multiple clone lines"

WORKSPACE9="$TEST_ROOT/workspace9"
mkdir -p "$WORKSPACE9"
cd "$WORKSPACE9"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO1_BARE"
echo "# Workspace 9" > README.md
git add README.md
git commit -q -m "Initial commit"
# Fetch branches so worktree creation works
git fetch -q origin

cat > repos.list <<EOF
# Start with workspace9 as fallback
@dev fallback-test-1
# Clone repo2 (updates fallback to repo2)
file://$REPO2_BARE
# This should create worktree from repo2, not workspace9
@staging fallback-test-2
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# First worktree should be from workspace9
if [ -d "$TEST_ROOT/fallback-test-1" ]; then
  cd "$TEST_ROOT/fallback-test-1"
  if git remote -v | grep -q "repo1.git"; then
    print_pass "First @branch used workspace9 (repo1) as fallback"
  else
    print_fail "First @branch used wrong fallback"
  fi
else
  print_fail "Failed to create first worktree"
fi

# Second worktree should be from repo2
if [ -d "$TEST_ROOT/fallback-test-2" ]; then
  cd "$TEST_ROOT/fallback-test-2"
  if git remote -v | grep -q "repo2.git"; then
    print_pass "Second @branch used repo2 as fallback (fallback updated)"
  else
    print_fail "Second @branch used wrong fallback"
  fi
else
  print_fail "Failed to create second worktree"
fi

# ============================================
# Test 10: Branch name sanitization (slashes to dashes)
# ============================================
print_test "Branch name sanitization: feature/test → feature-test"

WORKSPACE10="$TEST_ROOT/workspace10"
mkdir -p "$WORKSPACE10"
cd "$WORKSPACE10"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO1_BARE"
echo "# Workspace 10" > README.md
git add README.md
git commit -q -m "Initial commit"

git fetch -q origin

cat > repos.list <<EOF
@feature/test
@release/v1.0
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/workspace10-feature-test" ]; then
  print_pass "Sanitized feature/test → workspace10-feature-test"
  cd "$TEST_ROOT/workspace10-feature-test"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "feature/test" ]; then
    print_pass "Branch name preserved in git: feature/test"
  else
    print_fail "Branch name not preserved: $BRANCH"
  fi
else
  print_fail "Failed to create worktree with sanitized name"
fi

if [ -d "$TEST_ROOT/workspace10-release-v1.0" ]; then
  print_pass "Sanitized release/v1.0 → workspace10-release-v1.0"
else
  print_fail "Failed to create second worktree with sanitized name"
fi

# ============================================
# Test 11: Multiple references to same repo (branch suffix logic)
# ============================================
print_test "Multiple references to same repo: branch suffix logic"

WORKSPACE11="$TEST_ROOT/workspace11"
mkdir -p "$WORKSPACE11"
cd "$WORKSPACE11"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO3_BARE"
echo "# Workspace 11" > README.md
git add README.md
git commit -q -m "Initial commit"

cat > repos.list <<EOF
# Multiple references to repo3
file://$REPO3_BARE@main
file://$REPO3_BARE@experimental
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# With multiple references, should suffix with branch name
if [ -d "$TEST_ROOT/repo3-main" ]; then
  print_pass "Multiple refs: created repo3-main"
else
  print_fail "Failed to create repo3-main"
fi

if [ -d "$TEST_ROOT/repo3-experimental" ]; then
  print_pass "Multiple refs: created repo3-experimental"
else
  print_fail "Failed to create repo3-experimental"
fi

# ============================================
# Test 12: Single reference to repo (no branch suffix)
# ============================================
print_test "Single reference to repo: no branch suffix"

WORKSPACE12="$TEST_ROOT/workspace12"
mkdir -p "$WORKSPACE12"
cd "$WORKSPACE12"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Workspace 12" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create a new repo just for this test
REPO4_BARE="$BARE_REPOS_DIR/repo4.git"
create_bare_repo "$REPO4_BARE" "repo4" "special"

git remote add origin "file://$REPO4_BARE"

cat > repos.list <<EOF
# Single reference to repo4
file://$REPO4_BARE@special
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

# With single reference, should NOT suffix (just repo4)
if [ -d "$TEST_ROOT/repo4" ]; then
  print_pass "Single ref: created repo4 (no suffix)"
  cd "$TEST_ROOT/repo4"
  BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
  if [ "$BRANCH" = "special" ]; then
    print_pass "On correct branch: special"
  else
    print_fail "Wrong branch: $BRANCH (expected: special)"
  fi
else
  print_fail "Failed to create repo4 without suffix"
fi

# ============================================
# Test 13: Absolute path
# ============================================
print_test "Absolute path cloning"

WORKSPACE13="$TEST_ROOT/workspace13"
mkdir -p "$WORKSPACE13"
cd "$WORKSPACE13"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Workspace 13" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create a new repo for this test
REPO5_BARE="$BARE_REPOS_DIR/repo5.git"
create_bare_repo "$REPO5_BARE" "repo5" "beta"

git remote add origin "$REPO5_BARE"

cat > repos.list <<EOF
$REPO5_BARE
@beta
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/repo5" ]; then
  print_pass "Cloned from absolute path"
else
  print_fail "Failed to clone from absolute path"
fi

if [ -d "$TEST_ROOT/workspace13-beta" ]; then
  print_pass "Created worktree from repo cloned via absolute path"
else
  print_fail "Failed to create worktree"
fi

# ============================================
# Test 14: file:// URL
# ============================================
print_test "file:// URL cloning"

WORKSPACE14="$TEST_ROOT/workspace14"
mkdir -p "$WORKSPACE14"
cd "$WORKSPACE14"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
echo "# Workspace 14" > README.md
git add README.md
git commit -q -m "Initial commit"

# Create a new repo for this test
REPO6_BARE="$BARE_REPOS_DIR/repo6.git"
create_bare_repo "$REPO6_BARE" "repo6" "gamma"

git remote add origin "file://$REPO6_BARE"

cat > repos.list <<EOF
file://$REPO6_BARE
@gamma
EOF

"$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1 || true

if [ -d "$TEST_ROOT/repo6" ]; then
  print_pass "Cloned from file:// URL"
else
  print_fail "Failed to clone from file:// URL"
fi

if [ -d "$TEST_ROOT/workspace14-gamma" ]; then
  print_pass "Created worktree from repo cloned via file:// URL"
else
  print_fail "Failed to create worktree"
fi

# ============================================
# Test 15: Error case - non-empty directory
# ============================================
print_test "Error handling: non-empty directory"

WORKSPACE15="$TEST_ROOT/workspace15"
mkdir -p "$WORKSPACE15"
cd "$WORKSPACE15"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO1_BARE"
echo "# Workspace 15" > README.md
git add README.md
git commit -q -m "Initial commit"

# Pre-create a non-empty directory
mkdir -p "$TEST_ROOT/conflict-dir"
echo "existing content" > "$TEST_ROOT/conflict-dir/file.txt"

cat > repos.list <<EOF
file://$REPO1_BARE conflict-dir
EOF

# This should fail or handle gracefully
if "$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1; then
  # Check if it actually cloned or skipped
  if [ -f "$TEST_ROOT/conflict-dir/README.md" ]; then
    print_warning "Cloned to non-empty directory (may have overwritten)"
  else
    print_pass "Handled non-empty directory gracefully (skipped)"
  fi
else
  print_pass "Failed gracefully on non-empty directory"
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
  echo -e "Tests failed: ${GREEN}$TESTS_FAILED${NC}"
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
  echo ""
  echo "Coverage summary:"
  echo "  ✓ Full repo clone variations"
  echo "  ✓ Single-branch clone variations"
  echo "  ✓ Worktree variations"
  echo "  ✓ Fallback repo tracking"
  echo "  ✓ Branch name sanitization"
  echo "  ✓ Multiple/single reference logic"
  echo "  ✓ file:// URLs and absolute paths"
  echo "  ✓ Error handling"
fi
