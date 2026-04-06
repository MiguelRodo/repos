#!/usr/bin/env bash
# tests/test-credential-crlf.sh — Test CRLF handling in credential parsing

set -Eeuo pipefail

# --- Colors for output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

print_header() { echo -e "\n=== $1 ==="; }
print_pass() { echo -e "  ${GREEN}PASS${NC}: $1"; }
print_fail() { echo -e "  ${RED}FAIL${NC}: $1"; }

# 1. Test Windows-style CRLF parsing from mock git credential fill
print_header "Test: CRLF handling in git credential fill"

creds=$'username=joe\r\npassword=secret=token\r\n'
# Logic from scripts/helper/create-repos.sh:
EXTRACTED_USER=$(printf '%s\n' "$creds" | tr -d '\r' | sed -n 's/^username=//p' | tr -d '\n')
EXTRACTED_TOKEN=$(printf '%s\n' "$creds" | tr -d '\r' | sed -n 's/^password=//p' | tr -d '\n')

if [ "$EXTRACTED_USER" = "joe" ] && [ "$EXTRACTED_TOKEN" = "secret=token" ]; then
  print_pass "CRLF correctly handled and values extracted without truncation."
else
  print_fail "Parsing failed."
  exit 1
fi

# 2. Test environment variable sanitization
print_header "Test: Environment variable sanitization"
GH_USER=$'admin\r\nInjected: user'
GH_TOKEN=$'token\nInjected: token'

# Logic from scripts/helper/create-repos.sh:
SANITIZED_USER=$(printf '%s\n' "$GH_USER" | tr -d '\r\n')
SANITIZED_TOKEN=$(printf '%s\n' "$GH_TOKEN" | tr -d '\r\n')

if [[ "$SANITIZED_USER" == *$'\n'* ]] || [[ "$SANITIZED_USER" == *$'\r'* ]]; then
  print_fail "User variable still contains CRLF!"
  exit 1
elif [[ "$SANITIZED_TOKEN" == *$'\n'* ]] || [[ "$SANITIZED_TOKEN" == *$'\r'* ]]; then
  print_fail "Token variable still contains CRLF!"
  exit 1
else
  print_pass "Environment variables correctly sanitized (CRLF stripped)."
fi

echo -e "\n${GREEN}All credential security tests passed!${NC}"
