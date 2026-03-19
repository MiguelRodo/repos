#!/usr/bin/env bash
# tests/test-add-branch-security.sh — Verify scripts/add-branch.sh hardening
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ADD_BRANCH_SCRIPT="$PROJECT_ROOT/scripts/add-branch.sh"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_pass() { printf "${GREEN}✓ PASS: %s${NC}\n" "$1"; }
print_fail() { printf "${RED}❌ FAIL: %s${NC}\n" "$1"; exit 1; }

# Create a temporary environment for testing
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Setting up test environment..."
cd "$TEST_DIR"
mkdir -p base_repo/scripts/helper
cp "$ADD_BRANCH_SCRIPT" base_repo/scripts/add-branch.sh
cp "$PROJECT_ROOT/scripts/helper/vscode-workspace-add.sh" base_repo/scripts/helper/

cd base_repo
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git commit -q --allow-empty -m "Initial commit"
# Mock origin
mkdir -p ../origin_repo
cd ../origin_repo
git init -q --bare
cd ../base_repo
git remote add origin ../origin_repo

echo "Running security tests for add-branch.sh..."

# Test 1: Malicious branch names (leading hyphens)
# Note: In the new parser, if a hyphenated name is passed without --,
# it's caught as an "Unknown option". If passed with --, it's caught as an
# "invalid branch name" by the explicit hyphen check.
echo "  Testing hyphenated branch name WITHOUT --"
set +o pipefail
OUTPUT=$(bash scripts/add-branch.sh "-any-hyphen" 2>&1) || true
if echo "$OUTPUT" | grep -q "Unknown option"; then
  print_pass "Correctly rejected hyphenated branch name as unknown option"
else
  print_fail "Failed to reject hyphenated branch name without --"
fi
set -o pipefail

echo "  Testing hyphenated branch name WITH --"
set +o pipefail
OUTPUT=$(bash scripts/add-branch.sh -- "-any-hyphen" 2>&1) || true
if echo "$OUTPUT" | grep -q "is not a valid Git branch name"; then
  print_pass "Correctly rejected hyphenated branch name even with --"
else
  print_fail "Failed to reject hyphenated branch name with --"
fi
set -o pipefail

# Test 2: Argument parser hardening with --
echo "  Testing argument parser with --"
# Should treat --help as a branch name and reject it with validation error,
# not show the help message.
set +o pipefail
OUTPUT=$(bash scripts/add-branch.sh -- --help 2>&1) || true
if echo "$OUTPUT" | grep -q "is not a valid Git branch name"; then
  print_pass "Successfully used -- to treat --help as branch name"
else
  # If it showed help or had another error, it's a failure
  print_fail "Failed to correctly handle -- terminator"
fi
set -o pipefail

# Test 3: Path traversal in target-directory
echo "  Testing path traversal in target-directory"
set +o pipefail
OUTPUT=$(bash scripts/add-branch.sh "valid-branch" "../../outside" 2>&1) || true
if echo "$OUTPUT" | grep -q "cannot be absolute or contain '..'"; then
  print_pass "Correctly rejected path traversal in target-directory"
else
  print_fail "Failed to reject path traversal in target-directory"
fi
set -o pipefail

echo ""
echo "✅ All add-branch.sh security tests passed!"
