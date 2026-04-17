#!/usr/bin/env bash
# tests/test-http-token-stripping.sh
# Verifies that http:// URLs with embedded credentials are also stripped.

set -euo pipefail

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"
AUTH_SCRIPT="$PROJECT_ROOT/scripts/helper/codespaces-auth-add.sh"

# Load the scripts but only the normalization function
# We can't easily source them because they call main
# So we'll extract the function or use a wrapper

test_normalise() {
  local script="$1"
  local input="$2"
  local expected="$3"

  # Extract the function and run it in a subshell
  local result
  result=$(bash -c "
    $(sed -n '/^normalise_remote_to_https()/,/^}/p' "$script")
    normalise_remote_to_https '$input'
  ")

  if [ "$result" = "$expected" ]; then
    printf "  ✓ PASS: %s -> %s\n" "$input" "$result"
  else
    printf "  ✖ FAIL: %s -> %s (expected %s)\n" "$input" "$result" "$expected"
    return 1
  fi
}

echo "Testing http token stripping in clone-repos.sh..."
test_normalise "$CLONE_SCRIPT" "http://mytoken@github.com/owner/repo.git" "http://github.com/owner/repo"
test_normalise "$CLONE_SCRIPT" "http://user:pass@github.com/owner/repo" "http://github.com/owner/repo"

echo "Testing http token stripping in codespaces-auth-add.sh..."
test_normalise "$AUTH_SCRIPT" "http://mytoken@github.com/owner/repo.git" "http://github.com/owner/repo"
test_normalise "$AUTH_SCRIPT" "http://user:pass@github.com/owner/repo" "http://github.com/owner/repo"

echo "All http security normalization tests passed!"
