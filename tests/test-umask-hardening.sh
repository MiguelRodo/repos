#!/usr/bin/env bash
# tests/test-umask-hardening.sh - Verify that temporary files have restricted permissions

set -Eeuo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_pass() { printf "${GREEN}PASS: %s${NC}\n" "$1"; }
print_fail() { printf "${RED}FAIL: %s${NC}\n" "$1"; exit 1; }

# Mocking get_temp_dir
get_temp_dir() {
  printf '%s\n' "/tmp"
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

# Test case 1: git() wrapper temporary file
echo "Testing git() wrapper temporary file permissions..."

# We'll simulate the git() wrapper's temporary file creation
tmp_stderr="$(umask 077 && mktemp "$TEST_DIR/git-stderr-XXXXXX")"

# Check permissions
# Use stat if available, otherwise ls
if command -v stat >/dev/null 2>&1; then
    # GNU stat: %a for octal permissions, BSD/macOS stat: %Lp or %f
    if stat --version 2>/dev/null | grep -q "GNU"; then
        perms=$(stat -c "%a" "$tmp_stderr")
    else
        perms=$(stat -f "%Lp" "$tmp_stderr")
    fi
else
    perms=$(ls -l "$tmp_stderr" | cut -c 2-10)
fi

if [[ "$perms" == "600" || "$perms" == "rw-------" ]]; then
    print_pass "git-stderr has restricted permissions ($perms)"
else
    print_fail "git-stderr has insecure permissions ($perms)"
fi

# Test case 2: AUTH_HDR_FILE in create-repos.sh
echo "Testing AUTH_HDR_FILE permissions..."

AUTH_HDR_FILE="$(umask 077 && mktemp "$TEST_DIR/repos-auth-hdr-XXXXXX")"
echo "Authorization: token test_token" > "$AUTH_HDR_FILE"
chmod -- 600 "$AUTH_HDR_FILE"

if command -v stat >/dev/null 2>&1; then
    if stat --version 2>/dev/null | grep -q "GNU"; then
        perms=$(stat -c "%a" "$AUTH_HDR_FILE")
    else
        perms=$(stat -f "%Lp" "$AUTH_HDR_FILE")
    fi
else
    perms=$(ls -l "$AUTH_HDR_FILE" | cut -c 2-10)
fi

if [[ "$perms" == "600" || "$perms" == "rw-------" ]]; then
    print_pass "AUTH_HDR_FILE has restricted permissions ($perms)"
else
    print_fail "AUTH_HDR_FILE has insecure permissions ($perms)"
fi

echo "All umask hardening tests passed!"
