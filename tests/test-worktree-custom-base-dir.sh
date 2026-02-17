#!/usr/bin/env bash
# test-worktree-custom-base-dir.sh — Test worktree creation when base repo has custom directory
#
# PURPOSE:
#   Reproduce and verify fix for GitHub issue where @branch worktrees don't recognize
#   base repos that were cloned with custom directory names.
#
# SCENARIO:
#   1. Clone owner/repo@branch1 with custom directory "slides"
#   2. Create worktree @branch2 with custom directory "data"
#   3. Expected: @branch2 should create worktree from "slides" repo
#   4. Bug: @branch2 creates new full clone instead of worktree
#
# USAGE:
#   ./tests/test-worktree-custom-base-dir.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_test() { echo -e "${YELLOW}TEST:${NC} $1"; }
print_pass() { echo -e "  ${GREEN}✓${NC} $1"; }
print_fail() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# Locate clone-repos.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLONE_SCRIPT="$SCRIPT_DIR/../scripts/helper/clone-repos.sh"

if [ ! -f "$CLONE_SCRIPT" ]; then
  print_fail "clone-repos.sh not found at $CLONE_SCRIPT"
fi

# Create temp directory
TEST_ROOT="/tmp/test-worktree-custom-base-$$"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT"

# ============================================
# Setup: Create a bare repository with branches
# ============================================
print_test "Setting up test repository with branches"

REPO_BARE="$TEST_ROOT/lectures.git"
git init --bare -q "$REPO_BARE"

# Create a temp working copy to create branches
TEMP_WORK="$TEST_ROOT/temp_work"
mkdir -p "$TEMP_WORK"
cd "$TEMP_WORK"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$REPO_BARE"

# Create main branch
echo "# Lectures" > README.md
git add README.md
git commit -q -m "Initial commit"
git push -q origin HEAD:main

# Create branch1
git checkout -q -b branch1
echo "# Branch 1 content" > file1.txt
git add file1.txt
git commit -q -m "Add file1"
git push -q origin branch1

# Create branch2
git checkout -q -b branch2
echo "# Branch 2 content" > file2.txt
git add file2.txt
git commit -q -m "Add file2"
git push -q origin branch2

print_pass "Created bare repo with main, branch1, and branch2"

# ============================================
# Test: Clone with custom dir + worktree
# ============================================
print_test "Testing: MiguelRodo/lectures@branch1 slides + @branch2 data"

WORKSPACE="$TEST_ROOT/workspace"
mkdir -p "$WORKSPACE"
cd "$WORKSPACE"

# Create a minimal current repo (to satisfy clone-repos.sh expectations)
# Need to create a bare repo for workspace to have a remote
WORKSPACE_BARE="$TEST_ROOT/workspace.git"
git init --bare -q "$WORKSPACE_BARE"

git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin "file://$WORKSPACE_BARE"
echo "# Test workspace" > README.md
git add README.md
git commit -q -m "Init"
git push -q origin HEAD:main

# Create repos.list with the problematic scenario
cat > repos.list <<EOF
file://$REPO_BARE@branch1 slides
@branch2 data
EOF

# Run clone-repos.sh
if ! "$CLONE_SCRIPT" -f repos.list >/dev/null 2>&1; then
  print_fail "clone-repos.sh failed with exit code $?"
fi

# ============================================
# Verify: Check that the correct behavior happened
# ============================================

# 1. slides should exist and be a git repo with branch1
if [ ! -d "$TEST_ROOT/slides" ]; then
  print_fail "slides directory does not exist"
fi

cd "$TEST_ROOT/slides"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  print_fail "slides is not a git repository"
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ "$BRANCH" != "branch1" ]; then
  print_fail "slides is not on branch1 (found: $BRANCH)"
fi

print_pass "slides directory exists and is on branch1"

# 2. data should exist as a worktree (not a full clone)
if [ ! -d "$TEST_ROOT/data" ]; then
  print_fail "data directory does not exist"
fi

cd "$TEST_ROOT/data"
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  print_fail "data is not a git repository"
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [ "$BRANCH" != "branch2" ]; then
  print_fail "data is not on branch2 (found: $BRANCH)"
fi

# Check if data is a worktree (has .git file, not .git directory)
if [ -f "$TEST_ROOT/data/.git" ]; then
  print_pass "data is a worktree (.git is a file)"
else
  print_fail "data is NOT a worktree (.git is not a file)"
fi

# 3. Verify data's worktree points to slides
WORKTREE_INFO=$(cat "$TEST_ROOT/data/.git" | grep "gitdir:" | cut -d' ' -f2)
if echo "$WORKTREE_INFO" | grep -q "slides"; then
  print_pass "data worktree correctly points to slides base repo"
else
  print_fail "data worktree does NOT point to slides (points to: $WORKTREE_INFO)"
fi

# 4. Verify that NO additional clone of lectures was created
# (i.e., there should NOT be a "lectures" directory in TEST_ROOT)
if [ -d "$TEST_ROOT/lectures" ]; then
  print_fail "Unexpected 'lectures' directory found - script created unnecessary base clone"
fi

print_pass "No unnecessary 'lectures' base clone was created"

# ============================================
# Summary
# ============================================
echo ""
echo -e "${GREEN}✓ All tests passed!${NC}"
echo "  ✓ slides correctly cloned as single-branch"
echo "  ✓ data correctly created as worktree from slides"
echo "  ✓ No unnecessary base clone created"
echo ""
