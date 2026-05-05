#!/usr/bin/env bash
# tests/test-codespaces-jsonc-fix.sh
# Specifically tests the JSONC parsing logic in codespaces-auth-add.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_test() {
  echo -e "${YELLOW}TEST: $1${NC}"
}

print_pass() {
  echo -e "${GREEN}✓ PASS: $1${NC}"
}

print_fail() {
  echo -e "${RED}✗ FAIL: $1${NC}"
  exit 1
}

# Project paths
ORIG_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CODESPACES_SCRIPT="$ORIG_PROJECT_ROOT/scripts/helper/codespaces-auth-add.sh"

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
cd "$TEST_ROOT"

# Mock git environment
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin https://github.com/owner/repo

# Create a problematic devcontainer.json with comments and trailing commas
# Pattern 1: Trailing comma followed by a comment
cat > devcontainer.json <<EOF
{
  "name": "Test Project",
  "customizations": {
    "codespaces": {
      "repositories": {
        "owner/existing": { "permissions": "read-all" }
      }
    }
  }, // trailing comma here
  // comment followed by closing brace
}
EOF

# Create repos.list
echo "owner/new" > repos.list

print_test "Handling comments and trailing commas in devcontainer.json"

# Run codespaces-auth-add.sh forcing python tool
if ! bash "$CODESPACES_SCRIPT" -f repos.list -d devcontainer.json -t python3 >/dev/null 2>&1; then
  # If python3 is not available, try python
  if ! bash "$CODESPACES_SCRIPT" -f repos.list -d devcontainer.json -t python >/dev/null 2>&1; then
     print_fail "codespaces-auth-add.sh failed to run"
  fi
fi

# Verify JSON is still valid and has the new repository
if ! command -v jq >/dev/null 2>&1; then
  print_fail "jq is required for verification"
fi

if ! jq . devcontainer.json >/dev/null 2>&1; then
  print_fail "Resulting devcontainer.json is not valid JSON"
  cat devcontainer.json
fi

if jq -e '.customizations.codespaces.repositories["owner/new"]' devcontainer.json >/dev/null; then
  print_pass "Successfully updated devcontainer.json with problematic JSONC patterns"
else
  print_fail "New repository not found in devcontainer.json"
fi

# Test Pattern 2: Multi-line comments
cat > devcontainer.json <<EOF
{
  "name": "Test Project",
  "customizations": {
    "codespaces": {
      "repositories": {
        "owner/existing": { "permissions": "read-all" },
      } /* multi-line
         comment */
    }
  }
}
EOF

if ! bash "$CODESPACES_SCRIPT" -f repos.list -d devcontainer.json -t python3 >/dev/null 2>&1; then
  if ! bash "$CODESPACES_SCRIPT" -f repos.list -d devcontainer.json -t python >/dev/null 2>&1; then
     print_fail "codespaces-auth-add.sh failed to run for Pattern 2"
  fi
fi

if ! jq . devcontainer.json >/dev/null 2>&1; then
  print_fail "Pattern 2: Resulting devcontainer.json is not valid JSON"
  cat devcontainer.json
fi

if jq -e '.customizations.codespaces.repositories["owner/new"]' devcontainer.json >/dev/null; then
  print_pass "Successfully handled multi-line comments and trailing commas"
else
  print_fail "Pattern 2: New repository not found"
fi

echo -e "${GREEN}All JSONC fix tests passed!${NC}"
