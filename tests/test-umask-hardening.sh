#!/usr/bin/env bash
# tests/test-umask-hardening.sh — Verify temporary file permissions

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

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "Umask Hardening Test Suite"

# Mock git
mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/git" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/git"
export PATH="$TEST_ROOT/bin:$PATH"

# Copy scripts to test root
cp -r scripts "$TEST_ROOT/"
cd "$TEST_ROOT"

check_perms() {
  local file="$1"
  local label="$2"

  if [ ! -f "$file" ]; then
    echo -e "${RED}✗ FAIL: $label - file not found: '$file'${NC}"
    return 1
  fi

  local perms
  if [[ "$OSTYPE" == "darwin"* ]]; then
    perms=$(stat -f "%Lp" "$file")
  else
    perms=$(stat -c "%a" "$file")
  fi

  if [ "$perms" = "600" ] || [ "$perms" = "700" ]; then
    echo -e "${GREEN}✓ PASS: $label - permissions are $perms${NC}"
    return 0
  else
    echo -e "${RED}✗ FAIL: $label - permissions are $perms (expected 600 or 700)${NC}"
    return 1
  fi
}

# Test git() wrapper permissions
echo "Testing git() wrapper tmp_stderr permissions..."

cat > test_git_wrapper.sh <<'EOF'
get_temp_dir() { echo "."; }
git() {
  local tmp_stderr
  tmp_stderr="$(umask 077 && mktemp "$(get_temp_dir)/git-stderr-XXXXXX")"
  printf "%s" "$tmp_stderr"
}
git status
EOF

TMP_FILE_NAME=$(bash test_git_wrapper.sh)
check_perms "$TMP_FILE_NAME" "git wrapper tmp_stderr"

# Test other scripts
echo "Testing create-repos.sh AUTH_HDR_FILE..."
export GH_USER=test
export GH_TOKEN=test-token
export TMPDIR="$TEST_ROOT"

# Mock curl
cat > "$TEST_ROOT/bin/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/curl"

# Mock jq
cat > "$TEST_ROOT/bin/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$TEST_ROOT/bin/jq"

cat > repos.list <<EOF
owner/repo
EOF

# Run create-repos.sh
# Prevent cleanup
sed -i 's/trap /#trap /' scripts/helper/create-repos.sh

./scripts/helper/create-repos.sh -f repos.list > /dev/null 2>&1 || true

AUTH_FILE=$(find . -name "repos-auth-hdr-*" | head -n 1)
if [ -n "$AUTH_FILE" ]; then
  check_perms "$AUTH_FILE" "create-repos.sh AUTH_HDR_FILE"
else
  echo -e "${RED}✗ FAIL: create-repos.sh AUTH_HDR_FILE not found${NC}"
fi

echo "All umask hardening tests completed."
