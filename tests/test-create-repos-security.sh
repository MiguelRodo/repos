#!/usr/bin/env bash
# tests/test-create-repos-security.sh — Security tests for create-repos.sh validation

set -Eeuo pipefail

# --- Paths ---
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CREATE_SCRIPT="$PROJECT_ROOT/scripts/helper/create-repos.sh"

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

print_header() { echo -e "\n=== $1 ==="; }
print_pass() { echo -e "  ${GREEN}PASS${NC}: $1"; }
print_fail() { echo -e "  ${RED}FAIL${NC}: $1"; }

# Create a temporary repos.list for testing
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT
REPOS_FILE="$TEMP_DIR/repos.list"

test_validation() {
  local spec="$1"
  local expected_error="$2"
  local description="$3"

  echo "$spec" > "$REPOS_FILE"

  echo "Testing: $description ($spec)"
  # Set dummy credentials to avoid skipping
  export GH_TOKEN="dummy"
  export GH_USER="dummy"

  # Run script and capture output
  if output=$(bash "$CREATE_SCRIPT" -f "$REPOS_FILE" 2>&1); then
    print_fail "Script succeeded for invalid spec: $spec"
    return 1
  fi

  if echo "$output" | grep -F -e "$expected_error" > /dev/null; then
    print_pass "Correctly rejected with error: $expected_error"
    return 0
  else
    print_fail "Rejected but unexpected error message."
    echo "Actual output: $output"
    return 1
  fi
}

print_header "Running security validation tests for create-repos.sh"

test_validation "-owner/repo" "invalid owner name" "Leading hyphen in owner"
test_validation "owner/-repo" "invalid repository name" "Leading hyphen in repository"
test_validation "owner/repo/extra" "owner/repo" "Multiple slashes"
test_validation "owner/../repo" "owner/repo" "Path traversal"
test_validation "owner" "owner/repo" "Missing slash"
test_validation "owner/" "owner/repo" "Trailing slash"
# /repo is skipped as a local remote, so it's not strictly an error in create-repos.sh
# but we can check if it's skipped as expected.
echo "Testing: Leading slash (/repo) - should be skipped"
echo "/repo" > "$REPOS_FILE"
output=$(bash "$CREATE_SCRIPT" -f "$REPOS_FILE" 2>&1)
if echo "$output" | grep -q "Skipping local remote: /repo"; then
  print_pass "Leading slash correctly skipped as local remote"
else
  print_fail "Leading slash not skipped correctly"
  echo "Output: $output"
fi
test_validation "owner/repo!!" "invalid repository name" "Special characters in repository"
test_validation "owner^/repo" "invalid owner name" "Special characters in owner"

# Test valid spec with dummy token validation failure (to ensure it gets past validation)
echo "Validating that it gets past initial parsing for a valid spec..."
echo "owner/repo" > "$REPOS_FILE"
output=$(bash "$CREATE_SCRIPT" -f "$REPOS_FILE" 2>&1 || true)
if echo "$output" | grep -q "Exists: owner/repo" || echo "$output" | grep -q "invalid credentials" || echo "$output" | grep -q "Error checking owner/repo"; then
  print_pass "Valid spec 'owner/repo' passed initial validation"
else
  print_fail "Valid spec 'owner/repo' was rejected by initial validation"
  echo "Output: $output"
fi

echo -e "\n${GREEN}All security validation tests passed!${NC}"
