#!/usr/bin/env bash
# test-update-branches.sh — Integration tests for `repos update-branches`
# Tests the Go binary's update-branches subcommand using local bare git remotes
# (no network required).

set -e

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Test counters ─────────────────────────────────────────────────────────────
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_header() { echo ""; echo "============================================"; echo "$1"; echo "============================================"; }
print_test()   { echo ""; echo -e "${YELLOW}TEST: $1${NC}"; TESTS_RUN=$((TESTS_RUN + 1)); }
print_pass()   { echo -e "${GREEN}✓ PASS: $1${NC}"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
print_fail()   { echo -e "${RED}✗ FAIL: $1${NC}"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
print_info()   { echo "ℹ️  $1"; }

# ── Locate the repos binary ───────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Build (or locate pre-built) binary.
REPOS_BIN="$PROJECT_ROOT/repos-bin"
if [ ! -x "$REPOS_BIN" ]; then
  print_info "Building repos binary..."
  (cd "$PROJECT_ROOT" && go build -o "$REPOS_BIN" ./cmd/repos/) || {
    echo "ERROR: failed to build repos binary" >&2; exit 1
  }
fi

print_header "repos update-branches Integration Tests"
print_info "Binary : $REPOS_BIN"
print_info "Project: $PROJECT_ROOT"

# ── Shared temp directory ─────────────────────────────────────────────────────
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"; rm -f "$REPOS_BIN"' EXIT

# ── Helper: create a bare remote + initial clone with a commit ────────────────
# Usage: make_repo <base_dir> <name>
# Creates:
#   <base_dir>/remotes/<name>.git   (bare)
#   <base_dir>/repos/<name>         (clone tracking origin/main)
make_repo() {
  local base="$1" name="$2"
  local remote="$base/remotes/${name}.git"
  local clone="$base/repos/$name"

  git init --bare -q "$remote"
  git clone -q "$remote" "$clone"
  cd "$clone"
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "init"
  # Push to whichever default branch git chose (main or master)
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git push -q -u origin "$branch"
  cd - > /dev/null
}

# ── Helper: push a new commit to the remote (so clone is behind) ─────────────
push_new_commit() {
  local base="$1" name="$2"
  local tmp_clone="$base/tmp-push-$name"

  git clone -q "$base/remotes/${name}.git" "$tmp_clone"
  cd "$tmp_clone"
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -q -m "remote update"
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git push -q origin "$branch"
  cd - > /dev/null
  rm -rf "$tmp_clone"
}

# ── Test 1: All repos already up to date ─────────────────────────────────────
print_header "Test 1: all repos already up to date"
T1="$TEST_DIR/t1"
mkdir -p "$T1/repos"

make_repo "$T1" "alpha"
make_repo "$T1" "beta"

print_test "up-to-date repos produce correct summary"
OUTPUT=$("$REPOS_BIN" update-branches --dir "$T1/repos" 2>&1)
echo "$OUTPUT"

# Parse summary counts
UP_TO_DATE=$(echo "$OUTPUT" | grep "Already up to date" | wc -l | tr -d ' ')
ERRORS=$(echo "$OUTPUT" | grep "Errors" | grep -v "^#" | awk '{print $NF}')

if [ "$ERRORS" = "0" ]; then
  print_pass "No errors reported"
else
  print_fail "Expected 0 errors, got: $ERRORS"
fi

TOTAL=$(echo "$OUTPUT" | grep "Total repos scanned" | awk '{print $NF}')
if [ "$TOTAL" = "2" ]; then
  print_pass "Total repos scanned = 2"
else
  print_fail "Expected Total=2, got: $TOTAL"
fi

# ── Test 2: One repo behind remote (should be updated) ───────────────────────
print_header "Test 2: one repo behind remote"
T2="$TEST_DIR/t2"
mkdir -p "$T2/repos"

make_repo "$T2" "repo-a"
make_repo "$T2" "repo-b"

# Push a new commit to repo-a's remote so the local clone is behind
push_new_commit "$T2" "repo-a"

print_test "repo behind remote is fast-forwarded"
OUTPUT=$("$REPOS_BIN" update-branches --dir "$T2/repos" 2>&1)
echo "$OUTPUT"

UPDATED=$(echo "$OUTPUT" | grep "Updated" | grep -v "^#\|Already\|Total" | awk '{print $NF}')
if [ "$UPDATED" = "1" ]; then
  print_pass "1 repo updated"
else
  print_fail "Expected 1 updated, summary line: $(echo "$OUTPUT" | grep 'Updated')"
fi

ERRORS2=$(echo "$OUTPUT" | grep "Errors" | grep -v "^#" | awk '{print $NF}')
if [ "$ERRORS2" = "0" ]; then
  print_pass "No errors"
else
  print_fail "Expected 0 errors, got: $ERRORS2"
fi

# ── Test 3: Dirty working tree is skipped ────────────────────────────────────
print_header "Test 3: dirty repo is skipped"
T3="$TEST_DIR/t3"
mkdir -p "$T3/repos"

make_repo "$T3" "clean"
make_repo "$T3" "dirty"

# Make dirty repo's working tree unclean
echo "unstaged change" > "$T3/repos/dirty/unstaged.txt"

print_test "dirty repo is counted as skipped"
OUTPUT=$("$REPOS_BIN" update-branches --dir "$T3/repos" 2>&1)
echo "$OUTPUT"

SKIPPED=$(echo "$OUTPUT" | grep "Skipped (dirty)" | awk '{print $NF}')
if [ "$SKIPPED" = "1" ]; then
  print_pass "1 repo skipped due to dirty working tree"
else
  print_fail "Expected 1 skipped (dirty), got: $SKIPPED"
fi

# ── Test 4: --jobs flag is accepted ──────────────────────────────────────────
print_header "Test 4: --jobs flag"
T4="$TEST_DIR/t4"
mkdir -p "$T4/repos"
make_repo "$T4" "solo"

print_test "--jobs 1 runs without error"
OUTPUT=$("$REPOS_BIN" update-branches --dir "$T4/repos" --jobs 1 2>&1)
if echo "$OUTPUT" | grep -q "Total repos scanned"; then
  print_pass "--jobs 1 accepted and summary shown"
else
  print_fail "--jobs 1 did not produce expected output: $OUTPUT"
fi

print_test "-j 2 shorthand is accepted"
OUTPUT=$("$REPOS_BIN" update-branches --dir "$T4/repos" -j 2 2>&1)
if echo "$OUTPUT" | grep -q "Total repos scanned"; then
  print_pass "-j 2 accepted and summary shown"
else
  print_fail "-j 2 did not produce expected output: $OUTPUT"
fi

# ── Test 5: Help flag ─────────────────────────────────────────────────────────
print_header "Test 5: --help flag"

print_test "--help exits 0 and shows usage"
if "$REPOS_BIN" update-branches --help 2>&1 | grep -q "Usage:"; then
  print_pass "--help shows usage"
else
  print_fail "--help did not show usage"
fi

# ── Test 6: Empty directory ───────────────────────────────────────────────────
print_header "Test 6: directory with no git repos"
T6="$TEST_DIR/t6"
mkdir -p "$T6/empty-dir"

print_test "no repos found message"
OUTPUT=$("$REPOS_BIN" update-branches --dir "$T6/empty-dir" 2>&1)
if echo "$OUTPUT" | grep -q "No git repositories found"; then
  print_pass "Correct 'no repos' message"
else
  print_fail "Expected 'No git repositories found', got: $OUTPUT"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
print_header "Test Summary"
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"

if [ "$TESTS_FAILED" -gt 0 ]; then
  echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
  echo ""
  echo -e "${RED}Some tests failed.${NC}"
  exit 1
else
  echo ""
  echo -e "${GREEN}All tests passed!${NC}"
fi
