#!/usr/bin/env bash
# tests/test-security-hardening.sh — Test security hardening measures
# Validates path traversal prevention and JSON injection mitigation

set -e

# Workaround for CI environment where jq might be missing or different
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for security hardening tests"
  exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_header() {
  echo ""
  echo "============================================"
  echo "$1"
  echo "============================================"
}

print_test() {
  echo ""
  echo -e "${YELLOW}TEST: $1${NC}"
  TESTS_RUN=$((TESTS_RUN + 1))
}

print_pass() {
  echo -e "${GREEN}✓ PASS: $1${NC}"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_fail() {
  echo -e "${RED}✗ FAIL: $1${NC}"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# Project paths
ORIG_PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Create temporary test directory
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

print_header "Security Hardening Test Suite"

# ============================================
# Setup: Mock environment
# ============================================
mkdir -p "$TEST_ROOT/scripts/helper"
cp -r "$ORIG_PROJECT_ROOT/scripts/"* "$TEST_ROOT/scripts/"
cd "$TEST_ROOT"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
git remote add origin https://github.com/owner/repo

CLONE_SCRIPT="./scripts/helper/clone-repos.sh"
CREATE_SCRIPT="./scripts/helper/create-repos.sh"
WORKSPACE_SCRIPT="./scripts/helper/vscode-workspace-add.sh"
CODESPACES_SCRIPT="./scripts/helper/codespaces-auth-add.sh"
PIPELINE_SCRIPT="./scripts/run-pipeline.sh"
INSTALL_R_DEPS_SCRIPT="./scripts/helper/install-r-deps.sh"

# Mock Rscript and jq (to ensure they are found in PATH if needed)
mkdir -p bin
cat > bin/Rscript <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x bin/Rscript
export PATH="$PWD/bin:$PATH"

# ============================================
# Test 1: Path Traversal in clone-repos.sh
# ============================================
print_test "Path traversal in clone-repos.sh"

cat > repos.list <<EOF
owner/repo/../../traversed
EOF

if "$CLONE_SCRIPT" -f repos.list 2>error.log; then
  print_fail "clone-repos.sh should have failed for traversal"
else
  if grep -q "Error: repository spec cannot contain '..'" error.log; then
    print_pass "clone-repos.sh blocked path traversal"
  else
    print_fail "clone-repos.sh failed but with wrong error message"
    cat error.log
  fi
fi

# ============================================
# Test 6: Glob Expansion in repos.list
# ============================================
print_test "Glob expansion in repos.list"

# Create a dummy file that would be matched by a glob
touch "$TEST_ROOT/pwned.list"

# Create a repos.list with a glob
cat > repos.list <<EOF
owner/*.list
EOF

# Run clone-repos.sh in debug mode and capture output
if "$CLONE_SCRIPT" -f repos.list --debug 2>error.log; then
  : # It might fail for other reasons, that's fine
fi

# Check if 'pwned.list' appeared in the debug output where repo_spec is parsed
if grep -q "pwned.list" error.log; then
  print_fail "Glob expansion occurred! 'pwned.list' found in output"
else
  print_pass "Glob expansion was disabled"
fi
rm "$TEST_ROOT/pwned.list"

# ============================================
# Test 2: Path Traversal in vscode-workspace-add.sh
# ============================================
print_test "Path traversal in vscode-workspace-add.sh"

cat > repos.list <<EOF
owner/repo/../../traversed
EOF

# Note: vscode-workspace-add.sh handles repos.list differently
if "$WORKSPACE_SCRIPT" -f repos.list 2>error.log; then
  print_fail "vscode-workspace-add.sh should have failed for traversal"
else
  if grep -q "Error: repository spec cannot contain '..'" error.log; then
    print_pass "vscode-workspace-add.sh blocked path traversal"
  else
    print_fail "vscode-workspace-add.sh failed but with wrong error message"
    cat error.log
  fi
fi

# ============================================
# Test 3: Path Traversal in codespaces-auth-add.sh
# ============================================
print_test "Path traversal in codespaces-auth-add.sh"

cat > repos.list <<EOF
owner/repo/../../traversed
EOF

if "$CODESPACES_SCRIPT" -f repos.list -d devcontainer.json 2>error.log; then
  # It might skip if devcontainer.json doesn't exist, but it should fail validation first
  print_fail "codespaces-auth-add.sh should have failed for traversal"
else
  if grep -q "Error: repository spec cannot contain '..'" error.log; then
    print_pass "codespaces-auth-add.sh blocked path traversal"
  else
    print_fail "codespaces-auth-add.sh failed but with wrong error message"
    cat error.log
  fi
fi

# ============================================
# Test 4: Path Traversal in create-repos.sh
# ============================================
print_test "Path traversal in create-repos.sh"

cat > repos.list <<EOF
owner/repo/../../traversed
EOF

if "$CREATE_SCRIPT" -f repos.list 2>error.log; then
  print_fail "create-repos.sh should have failed for traversal"
else
  if grep -q "Error: repository spec cannot contain '..'" error.log; then
    print_pass "create-repos.sh blocked path traversal"
  else
    print_fail "create-repos.sh failed but with wrong error message"
    cat error.log
  fi
fi

# ============================================
# Test 5: JSON Injection Mitigation (Unit Test)
# ============================================
print_test "JSON injection mitigation (unit test)"

# We test the jq command used in create-repos.sh directly
MALICIOUS_REPO='test","private":false,"other":"'
this_repo_private=true
branch="main"

payload=$(jq -n --arg name "$MALICIOUS_REPO" --argjson priv "$this_repo_private" \
  --argjson init "$([ -n "$branch" ] && echo true || echo false)" \
  '{name: $name, private: $priv} + (if $init then {auto_init: true} else {} end)')

if echo "$payload" | jq . >/dev/null 2>&1; then
  print_pass "Constructed valid JSON even with malicious input"
  PARSED_NAME=$(echo "$payload" | jq -r .name)
  if [ "$PARSED_NAME" = "$MALICIOUS_REPO" ]; then
    print_pass "Malicious repo name was properly escaped"
  else
    print_fail "Parsed name mismatch"
  fi

  IS_PRIVATE=$(echo "$payload" | jq .private)
  if [ "$IS_PRIVATE" = "true" ]; then
    print_pass "Private flag was preserved"
  else
    print_fail "Private flag was overridden!"
  fi
else
  print_fail "Failed to construct valid JSON"
fi

# ============================================
# Test 7: Path Traversal in run-pipeline.sh (Workspace Folder)
# ============================================
print_test "Path traversal in run-pipeline.sh (workspace folder)"

# Create a malicious workspace file
cat > malicious.code-workspace <<EOF
{
  "folders": [
    { "path": "../../etc" }
  ]
}
EOF

# Mock jq for run-pipeline.sh to read our malicious workspace
if "$PIPELINE_SCRIPT" --script test.sh 2>error.log; then
   # Note: PIPELINE_SCRIPT expects PROJECT_ROOT relative workspace by default
   # But if it finds it, it should validate the paths
   :
fi

# Re-run with the malicious workspace
mv malicious.code-workspace entire-project.code-workspace
touch repos.list
# We need to make sure run-pipeline.sh finds jq
if "$PIPELINE_SCRIPT" -f repos.list --script test.sh 2>error.log; then
  print_fail "run-pipeline.sh should have failed for traversal in workspace"
else
  if grep -q "Error: invalid workspace folder path (too many '..')" error.log; then
    print_pass "run-pipeline.sh blocked path traversal in workspace"
  else
    print_fail "run-pipeline.sh failed but with wrong error message"
    cat error.log
  fi
fi

# ============================================
# Test 8: Path Traversal in install-r-deps.sh
# ============================================
print_test "Path traversal in install-r-deps.sh"

# Create a malicious workspace file
cat > entire-project.code-workspace <<EOF
{
  "folders": [
    { "path": "../../etc" }
  ]
}
EOF

# install-r-deps.sh should skip the invalid path and print a warning to stderr
if "$INSTALL_R_DEPS_SCRIPT" 2>error.log >/dev/null; then
  :
fi

if grep -q "Skipping invalid workspace folder path" error.log; then
  print_pass "install-r-deps.sh blocked path traversal"
else
  print_fail "install-r-deps.sh did not block path traversal or didn't log warning"
  cat error.log
fi

# ============================================
# Summary
# ============================================
print_header "Test Summary"
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
  exit 1
else
  echo -e "Tests failed: ${GREEN}0${NC}"
  echo ""
  echo "✅ All security hardening tests passed!"
fi
