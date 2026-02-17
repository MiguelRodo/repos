#!/usr/bin/env bash
# test-stale-worktree.sh — Test that setup-repos handles stale worktree references
# This test simulates the scenario where a worktree directory is manually deleted
# but git still has a record of it, then verifies the script can recover.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_header() {
  echo ""
  echo "============================================"
  echo "$1"
  echo "============================================"
}

print_test() {
  echo ""
  echo -e "${YELLOW}TEST: $1${NC}"
}

print_pass() {
  echo -e "${GREEN}✓ PASS: $1${NC}"
}

print_fail() {
  echo -e "${RED}✗ FAIL: $1${NC}"
  exit 1
}

print_info() {
  echo "ℹ️  $1"
}

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

print_header "Stale Worktree Test Suite"
print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test: Stale worktree recovery
# ============================================
print_test "Stale worktree can be recovered"

cd "$TEST_DIR"

# 1. Create a test git repo
git init test-repo
cd test-repo
git config user.name "Test User"
git config user.email "test@example.com"
echo "# Test" > README.md
git add README.md
git commit -m "Initial commit"

# 2. Create a worktree
mkdir -p ../worktrees
git worktree add ../worktrees/test-branch -b test-branch
print_info "Created worktree at ../worktrees/test-branch"

# 3. Verify worktree exists
if git worktree list | grep -q "test-branch"; then
  print_info "Worktree is registered in git"
else
  print_fail "Worktree was not created successfully"
fi

# 4. Manually delete the worktree directory (simulating the problem)
rm -rf ../worktrees/test-branch
print_info "Manually deleted worktree directory"

# 5. Verify git still thinks worktree exists (stale reference)
if git worktree list | grep -q "test-branch"; then
  print_info "Git still has stale worktree reference (expected)"
else
  print_fail "Git doesn't have worktree reference (unexpected)"
fi

# 6. Try to add the worktree again - should fail without prune
if git worktree add ../worktrees/test-branch test-branch 2>/dev/null; then
  print_fail "Worktree add should have failed with stale reference"
else
  print_info "Worktree add failed as expected (stale reference)"
fi

# 7. Now prune and try again - this is what our script does
git worktree prune
print_info "Ran git worktree prune"

# 8. Verify stale reference is gone
if git worktree list | grep -q "test-branch"; then
  print_fail "Stale worktree reference still exists after prune"
else
  print_info "Stale worktree reference removed by prune"
fi

# 9. Now we should be able to add the worktree again
git worktree add ../worktrees/test-branch test-branch
print_info "Successfully added worktree after prune"

# 10. Verify worktree exists and works
if [ -e ../worktrees/test-branch/.git ]; then
  print_pass "Worktree recovered successfully"
else
  print_fail "Worktree was not created after prune"
fi

# ============================================
# Test: clone-repos.sh handles stale worktree
# ============================================
print_test "clone-repos.sh handles stale worktree automatically"

cd "$TEST_DIR"
rm -rf *

# 1. Create a test repo with repos.list
git init main-repo
cd main-repo
git config user.name "Test User"
git config user.email "test@example.com"

# Set up git remote (required for clone-repos.sh)
git remote add origin "https://github.com/test/main-repo.git" || true

echo "# Main Repo" > README.md
git add README.md
git commit -m "Initial commit"

# Create repos.list with a worktree line
cat > repos.list <<'EOF'
# Test worktree
@test-branch
EOF

# Set GH_TOKEN for the test (dummy value is fine - we're not actually cloning remote repos)
export GH_TOKEN="test_token_for_local_testing"

# 2. First run - create the worktree normally
"$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list
print_info "First run: created worktree"

# Verify worktree was created
if [ -e ../main-repo-test-branch/.git ]; then
  print_info "Worktree created at ../main-repo-test-branch"
else
  print_fail "Worktree was not created"
fi

# 3. Manually delete the worktree directory
rm -rf ../main-repo-test-branch
print_info "Manually deleted worktree directory"

# 4. Second run - should detect and recover from stale worktree
if "$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list; then
  print_info "clone-repos.sh completed successfully"
else
  print_fail "clone-repos.sh failed to handle stale worktree"
fi

# 5. Verify worktree was recreated
if [ -e ../main-repo-test-branch/.git ]; then
  print_pass "clone-repos.sh recovered from stale worktree"
else
  print_fail "Worktree was not recreated after stale reference"
fi

echo ""
echo "============================================"
echo -e "${GREEN}All tests passed!${NC}"
echo "============================================"
