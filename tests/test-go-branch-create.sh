#!/usr/bin/env bash
# tests/test-go-branch-create.sh — Integration tests for `repos branch-create` Go subcommand
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Always build the binary from the current source so the test exercises the
# code under test rather than any installed system version.
REPOS_BIN=""
TMP_BIN=$(mktemp)
trap 'rm -f "$TMP_BIN"' EXIT
if go build -o "$TMP_BIN" "$PROJECT_ROOT/cmd/repos" 2>/dev/null; then
  REPOS_BIN="$TMP_BIN"
else
  echo "SKIP: could not build repos binary (go not available or build failed)"
  exit 0
fi

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_pass() { printf "${GREEN}✓ PASS: %s${NC}\n" "$1"; }
print_fail() { printf "${RED}❌ FAIL: %s${NC}\n" "$1"; exit 1; }

# --- Helper: create a minimal local git repo with a bare origin ---
make_repo() {
  local base="$1"
  mkdir -p "$base"
  git init --bare "$base/origin.git" -q
  git clone "$base/origin.git" "$base/repo" -q
  cd "$base/repo"
  git config user.email "test@example.com"
  git config user.name "Test"
  git commit --allow-empty -m "Initial commit" -q
  git push origin HEAD:main -q 2>/dev/null || git push origin HEAD:master -q 2>/dev/null || true
  cd - >/dev/null
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Building test environment..."
make_repo "$TEST_DIR"

# ---------------------------------------------------------------------------
echo "Running repos branch-create Go subcommand tests..."

# Test 1: Help flag
OUTPUT=$("$REPOS_BIN" branch-create --help 2>&1) || true
if echo "$OUTPUT" | grep -q "branch-name"; then
  print_pass "Help flag shows usage"
else
  print_fail "Help flag did not show expected usage"
fi

# Test 2: Missing branch name
OUTPUT=$("$REPOS_BIN" branch-create 2>&1) || true
if echo "$OUTPUT" | grep -q "branch-name is required"; then
  print_pass "Missing branch name gives error"
else
  print_fail "Missing branch name did not produce expected error"
fi

# Test 3: Hyphenated branch name (treated as unknown option)
OUTPUT=$("$REPOS_BIN" branch-create "-bad-branch" 2>&1) || true
if echo "$OUTPUT" | grep -q "unknown option"; then
  print_pass "Hyphenated branch name rejected as unknown option"
else
  print_fail "Hyphenated branch name was not rejected"
fi

# Test 4: Hyphenated branch name after --
OUTPUT=$("$REPOS_BIN" branch-create -- "-bad-branch" 2>&1) || true
if echo "$OUTPUT" | grep -q "is not a valid Git branch name"; then
  print_pass "Hyphenated branch name after -- rejected as invalid"
else
  print_fail "Hyphenated branch name after -- was not rejected"
fi

# Test 5: Path traversal in target directory
cd "$TEST_DIR/repo"
OUTPUT=$("$REPOS_BIN" branch-create valid-branch "../../outside" 2>&1) || true
if echo "$OUTPUT" | grep -q "cannot be absolute"; then
  print_pass "Path traversal in target directory rejected"
else
  print_fail "Path traversal in target directory was not rejected"
fi

# Test 6: --branch flag not implemented (flag before positional)
OUTPUT=$("$REPOS_BIN" branch-create -b test-br 2>&1) || true
if echo "$OUTPUT" | grep -q "not yet implemented"; then
  print_pass "--branch (-b) before positional reports not implemented"
else
  print_fail "--branch before positional did not report not implemented"
fi

# Test 7: --branch flag not implemented (flag after positional)
OUTPUT=$("$REPOS_BIN" branch-create test-br --branch 2>&1) || true
if echo "$OUTPUT" | grep -q "not yet implemented"; then
  print_pass "--branch after positional reports not implemented"
else
  print_fail "--branch after positional did not report not implemented"
fi

# Test 8: Successful worktree creation (default target dir)
cd "$TEST_DIR/repo"
"$REPOS_BIN" branch-create feature-x >/dev/null 2>&1
if [ -d "$TEST_DIR/repo-feature-x" ]; then
  print_pass "Worktree created at default location"
else
  print_fail "Worktree not found at expected default location"
fi

# Test 9: @branch added to repos.list
if grep -q "^@feature-x" "$TEST_DIR/repo/repos.list" 2>/dev/null; then
  print_pass "@feature-x added to repos.list"
else
  print_fail "@feature-x not found in repos.list"
fi

# Test 10: Destination already exists
OUTPUT=$("$REPOS_BIN" branch-create feature-x 2>&1) || true
if echo "$OUTPUT" | grep -q "destination already exists"; then
  print_pass "Duplicate destination rejected"
else
  print_fail "Duplicate destination was not rejected"
fi

# Test 11: Custom target directory
cd "$TEST_DIR/repo"
"$REPOS_BIN" branch-create analysis custom-analysis-dir >/dev/null 2>&1
if [ -d "$TEST_DIR/custom-analysis-dir" ]; then
  print_pass "Worktree created at custom target directory"
else
  print_fail "Worktree not found at custom target directory"
fi

# Test 12: repos.list entry with custom target dir
if grep -q "^@analysis custom-analysis-dir" "$TEST_DIR/repo/repos.list" 2>/dev/null; then
  print_pass "@analysis custom-analysis-dir added to repos.list"
else
  print_fail "repos.list entry with custom target dir not found"
fi

# Test 13: @branch already in repos.list — not duplicated
COUNT=$(grep -c "^@feature-x" "$TEST_DIR/repo/repos.list" 2>/dev/null || echo 0)
if [ "$COUNT" -eq 1 ]; then
  print_pass "No duplicate @feature-x entry in repos.list"
else
  print_fail "Duplicate @feature-x entry found in repos.list (count=$COUNT)"
fi

echo ""
echo "✅ All repos branch-create Go subcommand tests passed!"
