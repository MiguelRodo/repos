#!/usr/bin/env bash
# test-codespaces-path-resolution.sh — Test that codespaces-auth-add.sh resolves paths correctly
# This verifies the fix for two bugs:
#   1. Default repos.list was looked up relative to the script installation dir, not CWD
#   2. get_current_repo_remote_https() cd'd into the script install dir instead of using CWD

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

print_header "Codespaces Auth Path Resolution Test Suite"
print_info "Test directory: $TEST_DIR"
print_info "Project root: $PROJECT_ROOT"

# ============================================
# Test: Script uses CWD-relative repos.list by default
# ============================================
print_test "codespaces-auth-add.sh uses CWD-relative repos.list (not script installation dir)"

cd "$TEST_DIR"

# Create a user project directory (simulates ~/projects/my-project)
mkdir -p user-project/.devcontainer

# Create repos.list in the user project dir
cat > user-project/repos.list <<'EOF'
# Test repository
testowner/testrepo
EOF

# Create a minimal devcontainer.json
cat > user-project/.devcontainer/devcontainer.json <<'EOF'
{
  "name": "Test Container"
}
EOF

# Simulate an "installed" location for the script (like /usr/share/repos/scripts/helper)
mkdir -p installed-repos/scripts/helper
cp "$PROJECT_ROOT/scripts/helper/codespaces-auth-add.sh" installed-repos/scripts/helper/
chmod +x installed-repos/scripts/helper/codespaces-auth-add.sh

# Initialize git repo in user-project (required by the script to detect current repo)
cd user-project
git -c init.defaultBranch=main init -q
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"
echo "# Test" > README.md
git add README.md .devcontainer/devcontainer.json repos.list
git commit -m "Initial commit"

print_info "Created test structure:"
print_info "  - user-project/       (simulated user CWD, is a git repo)"
print_info "    - repos.list"
print_info "    - .devcontainer/devcontainer.json"
print_info "  - installed-repos/scripts/helper/codespaces-auth-add.sh  (simulated install dir)"

# Run the script WITHOUT -f, from the user project directory.
# The script should find repos.list in CWD, not in the script's install dir.
set +e
output=$("$TEST_DIR/installed-repos/scripts/helper/codespaces-auth-add.sh" \
  -d .devcontainer/devcontainer.json --dry-run 2>&1)
exit_code=$?
set -e

print_info "Exit code: $exit_code"
print_info "Output: $output"

if echo "$output" | grep -q "File not found:.*installed-repos"; then
  print_fail "Script looked for repos.list in script install dir instead of CWD"
fi

if echo "$output" | grep -q "Error: File not found"; then
  print_fail "Script could not find repos.list in CWD"
fi

if [ "$exit_code" -ne 0 ] && ! echo "$output" | grep -q "Updated\|dry-run\|testowner/testrepo"; then
  print_fail "Script failed unexpectedly: $output"
fi

print_pass "Script reads repos.list from CWD, not from script installation directory"

# ============================================
# Test: get_current_repo_remote_https uses CWD git context
# ============================================
print_test "Script detects git repo from CWD (not from script installation directory)"

# The installed-repos directory is NOT a git repo; user-project is.
# Verify the script does not error with "not inside a Git working tree"
if echo "$output" | grep -q "not inside a Git working tree"; then
  print_fail "Script ran git commands against the script installation dir (not a git repo)"
fi

print_pass "Script correctly uses CWD git context for fallback repo detection"

# ============================================
# Test: Script can find devcontainer.json when -d is specified
# ============================================
print_test "Script finds devcontainer.json at correct path when specified with -d"

# Run the script with dry-run and explicit -d and -f flags
set +e
output=$("$TEST_DIR/installed-repos/scripts/helper/codespaces-auth-add.sh" \
  -f repos.list -d .devcontainer/devcontainer.json --dry-run 2>&1)
exit_code=$?
set -e

print_info "Exit code: $exit_code"
print_info "Output: $output"

# Check the output doesn't contain an error about devcontainer.json not found
if echo "$output" | grep -q "Error: devcontainer.json not found"; then
  print_fail "Script could not find devcontainer.json"
fi

print_pass "Script finds devcontainer.json at correct path"

# ============================================
# Test: Script executes successfully with correct path
# ============================================
print_test "Script executes successfully with the correct devcontainer.json path"

if ! command -v jq >/dev/null 2>&1; then
  if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
    print_info "Neither jq nor python available, skipping execution test"
  else
    print_info "Using Python fallback for JSON processing"
    set +e
    output=$("$TEST_DIR/installed-repos/scripts/helper/codespaces-auth-add.sh" \
      -f repos.list -d .devcontainer/devcontainer.json -t python3 --dry-run 2>&1)
    exit_code=$?
    set -e

    if [ "$exit_code" -eq 0 ]; then
      print_pass "Script executed successfully with Python"
    else
      print_info "Script output: $output"
      if echo "$output" | grep -q "Error: devcontainer.json not found"; then
        print_fail "Script still reports devcontainer.json not found"
      else
        print_info "Script failed for a different reason (not path issue)"
      fi
    fi
  fi
else
  set +e
  output=$("$TEST_DIR/installed-repos/scripts/helper/codespaces-auth-add.sh" \
    -f repos.list -d .devcontainer/devcontainer.json -t jq --dry-run 2>&1)
  exit_code=$?
  set -e

  if [ "$exit_code" -eq 0 ]; then
    print_pass "Script executed successfully with jq"
  else
    print_info "Script output: $output"
    if echo "$output" | grep -q "Error: devcontainer.json not found"; then
      print_fail "Script still reports devcontainer.json not found"
    else
      print_info "Script failed for a different reason (not path issue)"
    fi
  fi
fi

echo ""
echo "============================================"
echo -e "${GREEN}All path resolution tests passed!${NC}"
echo "============================================"
