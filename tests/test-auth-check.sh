#!/usr/bin/env bash
# test-auth-check.sh — Test that clone-repos fails early with helpful message when auth is missing
# This test verifies the non-interactive authentication check works correctly

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

print_header "Authentication Check Test Suite"
print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test: Auth check fails without credentials
# ============================================
print_test "Auth check fails when no credentials are available"

cd "$TEST_DIR"

# 1. Create a minimal test repo
git init test-repo
cd test-repo
git config user.name "Test User"
git config user.email "test@example.com"

# Set up git remote
git remote add origin "https://github.com/test/test-repo.git" || true

echo "# Test" > README.md
git add README.md
git commit -m "Initial commit"

# Create minimal repos.list (doesn't actually need to clone, just trigger auth check)
cat > repos.list <<'EOF'
# Empty file to test auth check
EOF

# 2. Unset all auth-related environment variables
unset GH_TOKEN
unset GITHUB_TOKEN
unset GH_USER
export SSH_AUTH_SOCK=""  # Disable SSH agent

print_info "Cleared all authentication environment variables"

# 3. Run clone-repos.sh - should fail with auth error
set +e
output=$("$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1)
exit_code=$?
set -e

print_info "Exit code: $exit_code"

# 4. Verify it failed (non-zero exit code)
if [ "$exit_code" -ne 0 ]; then
  print_info "Script failed as expected (exit code: $exit_code)"
else
  print_fail "Script should have failed without credentials"
fi

# 5. Verify error message contains helpful information
if echo "$output" | grep -q "No non-interactive GitHub authentication"; then
  print_pass "Error message mentions authentication issue"
else
  print_fail "Error message doesn't mention authentication"
fi

if echo "$output" | grep -q "GH_TOKEN"; then
  print_pass "Error message mentions GH_TOKEN"
else
  print_fail "Error message doesn't mention GH_TOKEN"
fi

# ============================================
# Test: Auth check passes with GH_TOKEN
# ============================================
print_test "Auth check passes when GH_TOKEN is set"

# Set a dummy token (doesn't need to be valid for the auth check to pass)
export GH_TOKEN="dummy_token_for_testing"

print_info "Set GH_TOKEN environment variable"

# Run with just the empty repos.list to verify auth check passes
set +e
output=$("$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1)
exit_code=$?
set -e

print_info "Exit code: $exit_code"

# Should succeed (or at least not fail on auth check)
# Exit code 0 means success (no repos to clone is success)
if [ "$exit_code" -eq 0 ]; then
  print_pass "Script passed auth check with GH_TOKEN set"
else
  # If it failed, check it's not due to auth
  if echo "$output" | grep -q "No non-interactive GitHub authentication"; then
    print_fail "Auth check failed even with GH_TOKEN set"
  else
    print_pass "Script passed auth check (failed for different reason)"
  fi
fi

# ============================================
# Test: Auth check with gh CLI
# ============================================
print_test "Auth check detects gh CLI authentication"

# This test is informational - we check if gh is available
if command -v gh >/dev/null 2>&1; then
  print_info "gh CLI is available on this system"
  
  # Check if gh is authenticated (don't fail if not)
  if gh auth status >/dev/null 2>&1; then
    print_info "gh CLI is authenticated"
    
    # Unset GH_TOKEN to test gh CLI path
    unset GH_TOKEN
    
    # Should still pass auth check via gh CLI
    set +e
    output=$("$PROJECT_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1)
    exit_code=$?
    set -e
    
    if [ "$exit_code" -eq 0 ] || ! echo "$output" | grep -q "No non-interactive GitHub authentication"; then
      print_pass "Auth check passed via gh CLI"
    else
      print_fail "Auth check failed with gh CLI authenticated"
    fi
  else
    print_info "gh CLI is not authenticated (skipping gh auth test)"
  fi
else
  print_info "gh CLI not available (skipping gh auth test)"
fi

echo ""
echo "============================================"
echo -e "${GREEN}All authentication tests passed!${NC}"
echo "============================================"
