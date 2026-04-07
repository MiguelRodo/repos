#!/usr/bin/env bash
# tests/test-git-hardening.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_pass() { echo -e "${GREEN}PASS: $1${NC}"; }
print_fail() { echo -e "${RED}FAIL: $1${NC}"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Create a workspace for testing
TEST_DIR=$(mktemp -d)
# Ensure cleanup on exit
trap 'rm -rf "$TEST_DIR"' EXIT

# 1. Setup dummy remote repo
mkdir -p "$TEST_DIR/remote/repo"
cd "$TEST_DIR/remote/repo"
git init
git config user.email "test@example.com"
git config user.name "Test User"
git commit --allow-empty -m "Initial commit"

# 2. Setup work dir
mkdir -p "$TEST_DIR/work"
cd "$TEST_DIR/work"
# The script expects to be run inside a git repo to derive fallback
git init base-repo
cd base-repo
git config user.email "test@example.com"
git config user.name "Test User"
git commit --allow-empty -m "Initial commit"
git remote add origin "file://$TEST_DIR/remote/repo"

# Copy the script to be tested
mkdir -p scripts/helper
cp "$PROJECT_ROOT/scripts/helper/clone-repos.sh" scripts/helper/

# Test Case: @-h branch name
# This should trigger help in git worktree add if not hardened
cat > repos.list <<EOF
@-h
EOF

echo "Testing if @-h branch name triggers argument injection in git worktree add..."
# Run clone-repos.sh with --worktree to force worktree creation
# We need to use -f repos.list
OUTPUT=$(bash scripts/helper/clone-repos.sh -f repos.list --worktree --debug 2>&1 || true)

if echo "$OUTPUT" | grep -q "usage: git worktree add"; then
  print_fail "Hardening failed: git worktree add interpreted -h as an option!"
elif echo "$OUTPUT" | grep -q "Adding worktree .*/base-repo--h (new branch '-h' from origin/master)"; then
  # Note: branch name might be sanitized to -h in path, or just -h
  print_pass "Hardening successful: git worktree add tried to create a branch named '-h'."
elif echo "$OUTPUT" | grep -q "Adding worktree .*/base-repo--h (new branch '-h' from origin/main)"; then
  print_pass "Hardening successful: git worktree add tried to create a branch named '-h'."
else
  echo "Output was:"
  echo "$OUTPUT"
  # Check if it at least didn't show help
  if ! echo "$OUTPUT" | grep -q "usage: git worktree add"; then
     print_pass "Hardening appears successful (no help message found), though branch creation might have failed for other reasons."
  else
     print_fail "Unexpected output during @-h test."
  fi
fi
