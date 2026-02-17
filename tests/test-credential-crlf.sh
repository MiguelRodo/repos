#!/usr/bin/env bash
# test-credential-crlf.sh — Test that credential parsing handles CRLF line endings from Windows Git Credential Manager
# This test validates the fix for WSL2 users with Windows Git Credential Manager

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

print_header "Credential Parsing CRLF Test Suite"

# ============================================
# Test: Parsing credentials with CRLF endings
# ============================================
print_test "Credential extraction handles CRLF line endings"

# Simulate Windows Git Credential Manager output with CRLF line endings
# This is what WSL2 users see when using Windows Git Credential Manager
creds_with_crlf=$(printf 'protocol=https\r\nhost=github.com\r\nusername=testuser\r\npassword=ghp_testtoken123\r\n')

print_info "Simulating Windows Git Credential Manager output with CRLF"

# Test the extraction logic that's used in create-repos.sh (lines 121-123)
# This should work with the tr -d '\r' fix
GH_USER=$(printf '%s\n' "$creds_with_crlf" | tr -d '\r' | awk -F= '/^username=/ {print $2}')
GH_TOKEN=$(printf '%s\n' "$creds_with_crlf" | tr -d '\r' | awk -F= '/^password=/ {print $2}')

print_info "Extracted GH_USER: '${GH_USER}'"
print_info "Extracted GH_TOKEN: '${GH_TOKEN}'"

# Verify username was extracted correctly
if [ "$GH_USER" = "testuser" ]; then
  print_pass "Username extracted correctly from CRLF credentials"
else
  print_fail "Username extraction failed. Expected 'testuser', got '${GH_USER}'"
fi

# Verify token was extracted correctly
if [ "$GH_TOKEN" = "ghp_testtoken123" ]; then
  print_pass "Token extracted correctly from CRLF credentials"
else
  print_fail "Token extraction failed. Expected 'ghp_testtoken123', got '${GH_TOKEN}'"
fi

# Verify no trailing carriage returns
if printf '%s' "$GH_USER" | od -An -tx1 | grep -q '0d'; then
  print_fail "Username still contains carriage return (\\r)"
fi

if printf '%s' "$GH_TOKEN" | od -An -tx1 | grep -q '0d'; then
  print_fail "Token still contains carriage return (\\r)"
fi

print_pass "No carriage returns in extracted values"

# ============================================
# Test: Parsing credentials with LF endings (backwards compatibility)
# ============================================
print_test "Credential extraction still works with Unix LF line endings"

# Simulate Unix git credential output with LF line endings
creds_with_lf=$(printf 'protocol=https\nhost=github.com\nusername=unixuser\npassword=ghp_unixtoken456\n')

print_info "Testing with Unix-style LF line endings"

# Test the extraction logic
GH_USER=$(printf '%s\n' "$creds_with_lf" | tr -d '\r' | awk -F= '/^username=/ {print $2}')
GH_TOKEN=$(printf '%s\n' "$creds_with_lf" | tr -d '\r' | awk -F= '/^password=/ {print $2}')

print_info "Extracted GH_USER: '${GH_USER}'"
print_info "Extracted GH_TOKEN: '${GH_TOKEN}'"

# Verify username was extracted correctly
if [ "$GH_USER" = "unixuser" ]; then
  print_pass "Username extracted correctly from LF credentials"
else
  print_fail "Username extraction failed. Expected 'unixuser', got '${GH_USER}'"
fi

# Verify token was extracted correctly
if [ "$GH_TOKEN" = "ghp_unixtoken456" ]; then
  print_pass "Token extracted correctly from LF credentials"
else
  print_fail "Token extraction failed. Expected 'ghp_unixtoken456', got '${GH_TOKEN}'"
fi

echo ""
echo "============================================"
echo -e "${GREEN}All CRLF credential parsing tests passed!${NC}"
echo "============================================"
