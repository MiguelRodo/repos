#!/usr/bin/env bash
# tests/test-security-token-stripping.sh
# Verify that normalise_remote_to_https strips embedded credentials

set -euo pipefail

# Find the scripts
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)/scripts/helper"
CLONE_SCRIPT="$SCRIPT_DIR/clone-repos.sh"
AUTH_SCRIPT="$SCRIPT_DIR/codespaces-auth-add.sh"

# Function to extract and run the normalise_remote_to_https function from a script
test_normalization() {
  local script_path="$1"
  local test_url="$2"
  local expected_url="$3"

  # Extract the function using sed
  # We look for the start and end of the function.
  # This is fragile if the script structure changes significantly, but works for now.
  local func_body
  func_body=$(sed -n '/^normalise_remote_to_https() {/,/^}/p' "$script_path")

  # Create a temporary script to run the function
  local temp_script
  temp_script=$(mktemp)
  cat > "$temp_script" <<EOF
#!/usr/bin/env bash
$func_body
normalise_remote_to_https "$test_url"
EOF

  local result
  result=$(bash "$temp_script")
  rm -f "$temp_script"

  if [ "$result" = "$expected_url" ]; then
    printf "  ✓ PASS: %s -> %s\n" "$test_url" "$result"
    return 0
  else
    printf "  ✖ FAIL: %s -> %s (expected %s)\n" "$test_url" "$result" "$expected_url"
    return 1
  fi
}

FAILED=0

echo "Testing token stripping in clone-repos.sh..."
test_normalization "$CLONE_SCRIPT" "https://mytoken@github.com/owner/repo.git" "https://github.com/owner/repo" || FAILED=1
test_normalization "$CLONE_SCRIPT" "https://user:pass@github.com/owner/repo" "https://github.com/owner/repo" || FAILED=1
test_normalization "$CLONE_SCRIPT" "https://github.com/owner/repo.git" "https://github.com/owner/repo" || FAILED=1

echo "Testing token stripping in codespaces-auth-add.sh..."
test_normalization "$AUTH_SCRIPT" "https://mytoken@github.com/owner/repo.git" "https://github.com/owner/repo" || FAILED=1
test_normalization "$AUTH_SCRIPT" "https://user:pass@github.com/owner/repo" "https://github.com/owner/repo" || FAILED=1

if [ $FAILED -eq 0 ]; then
  echo "All security normalization tests passed!"
  exit 0
else
  echo "Security normalization tests failed!"
  exit 1
fi
