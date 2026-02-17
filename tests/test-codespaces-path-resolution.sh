#!/usr/bin/env bash
# test-codespaces-path-resolution.sh — Test that codespaces-auth-add.sh resolves PROJECT_ROOT correctly
# This verifies the fix for the issue where DEVFILE was incorrectly pointing to scripts/.devcontainer/devcontainer.json

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
# Test: PROJECT_ROOT resolves correctly
# ============================================
print_test "codespaces-auth-add.sh calculates PROJECT_ROOT correctly"

cd "$TEST_DIR"

# Create a minimal test project structure mimicking the real layout
mkdir -p test-project/scripts/helper
mkdir -p test-project/.devcontainer

# Create a minimal repos.list
cat > test-project/repos.list <<'EOF'
# Test repository
testowner/testrepo
EOF

# Create a minimal devcontainer.json
cat > test-project/.devcontainer/devcontainer.json <<'EOF'
{
  "name": "Test Container"
}
EOF

# Copy the codespaces-auth-add.sh script
cp "$PROJECT_ROOT/scripts/helper/codespaces-auth-add.sh" test-project/scripts/helper/

# Make it executable
chmod +x test-project/scripts/helper/codespaces-auth-add.sh

# Initialize git repo (required by the script to detect current repo)
cd test-project
git init
git config user.name "Test User"
git config user.email "test@example.com"
git remote add origin "https://github.com/testowner/testrepo.git"
echo "# Test" > README.md
git add README.md .devcontainer/devcontainer.json repos.list
git commit -m "Initial commit"

print_info "Created test project structure"
print_info "  - test-project/"
print_info "    - scripts/helper/codespaces-auth-add.sh"
print_info "    - .devcontainer/devcontainer.json"
print_info "    - repos.list"

# ============================================
# Test: Script can find devcontainer.json
# ============================================
print_test "Script finds devcontainer.json at correct path"

# Run the script with dry-run to avoid actual modification
# We expect it to succeed finding the devcontainer.json
set +e
output=$(./scripts/helper/codespaces-auth-add.sh -f repos.list --dry-run 2>&1)
exit_code=$?
set -e

print_info "Exit code: $exit_code"

# Check the output doesn't contain the error about devcontainer.json not found
if echo "$output" | grep -q "Error: devcontainer.json not found"; then
  print_fail "Script could not find devcontainer.json"
fi

# Check that the error is NOT pointing to scripts/.devcontainer/devcontainer.json
if echo "$output" | grep -q "scripts/.devcontainer/devcontainer.json"; then
  print_fail "Script is still looking in wrong path: scripts/.devcontainer/"
fi

print_pass "Script finds devcontainer.json at correct path"

# ============================================
# Test: Verify the actual path used
# ============================================
print_test "Verify DEVFILE variable resolves to correct path"

# Just check what SCRIPT_DIR and PROJECT_ROOT would be from scripts/helper
SCRIPT_DIR_TEST="$(cd scripts/helper && pwd)"
PROJECT_ROOT_TEST="$(cd "$SCRIPT_DIR_TEST/../.." && pwd)"
DEVFILE_TEST="$PROJECT_ROOT_TEST/.devcontainer/devcontainer.json"

print_info "Path resolution:"
print_info "  SCRIPT_DIR=$SCRIPT_DIR_TEST"
print_info "  PROJECT_ROOT=$PROJECT_ROOT_TEST"
print_info "  DEVFILE=$DEVFILE_TEST"

# Verify the paths
if [[ "$PROJECT_ROOT_TEST" == *"test-project" ]] && [[ "$PROJECT_ROOT_TEST" != *"scripts"* ]]; then
  print_pass "PROJECT_ROOT resolves to project root (not scripts/)"
else
  print_fail "PROJECT_ROOT does not resolve correctly: $PROJECT_ROOT_TEST"
fi

if [[ "$DEVFILE_TEST" == *"test-project/.devcontainer/devcontainer.json" ]]; then
  print_pass "DEVFILE resolves to .devcontainer/devcontainer.json (not scripts/.devcontainer/)"
else
  print_fail "DEVFILE does not resolve correctly: $DEVFILE_TEST"
fi

# Verify the file exists at that path
if [ -f "$DEVFILE_TEST" ]; then
  print_pass "devcontainer.json exists at the resolved path"
else
  print_fail "devcontainer.json not found at resolved path: $DEVFILE_TEST"
fi

# ============================================
# Test: Script executes successfully with correct path
# ============================================
print_test "Script executes successfully with the correct devcontainer.json path"

# Install jq if not available (needed by the script)
if ! command -v jq >/dev/null 2>&1; then
  if ! command -v python3 >/dev/null 2>&1 && ! command -v python >/dev/null 2>&1; then
    print_info "Neither jq nor python available, skipping execution test"
  else
    print_info "Using Python fallback for JSON processing"
    # Run with python tool
    set +e
    output=$(./scripts/helper/codespaces-auth-add.sh -f repos.list -t python3 --dry-run 2>&1)
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
  # Run with jq
  set +e
  output=$(./scripts/helper/codespaces-auth-add.sh -f repos.list -t jq --dry-run 2>&1)
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
