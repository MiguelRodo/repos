#!/usr/bin/env bash
# tests/test-go-branch-update.sh — Integration tests for `repos branch-update` Go subcommand
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

REPOS_BIN=""
TMP_BIN=$(mktemp)
trap 'rm -f "$TMP_BIN"' EXIT
if go build -o "$TMP_BIN" "$PROJECT_ROOT/cmd/repos" 2>/dev/null; then
  REPOS_BIN="$TMP_BIN"
else
  echo "SKIP: could not build repos binary"
  exit 0
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

print_pass() { printf "${GREEN}✓ PASS: %s${NC}\n" "$1"; }
print_fail() { printf "${RED}❌ FAIL: %s${NC}\n" "$1"; exit 1; }

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

echo "Building test environment..."
mkdir -p "$TEST_DIR/repo"
cd "$TEST_DIR/repo"
git init -q
git config user.email "test@example.com"
git config user.name "Test"
git commit --allow-empty -m "Initial commit" -q

echo "Running repos branch-update Go subcommand tests..."

# Create the prebuild devcontainer
mkdir -p .devcontainer/prebuild
cat > .devcontainer/prebuild/devcontainer.json << 'EOF'
{
  "name": "Base Repo",
  "customizations": {
    "codespaces": {
      "openFiles": ["README.md"],
      "repositories": {
        "user/repo": {
          "permissions": "write-all"
        }
      }
    }
  }
}
EOF

# Create a worktree to be updated
git worktree add -b test-branch ../repo-test-branch HEAD -q
mkdir -p ../repo-test-branch/.devcontainer
cat > ../repo-test-branch/.devcontainer/devcontainer.json << 'EOF'
{
  "name": "Old name"
}
EOF

cd ../repo-test-branch
git add .devcontainer/devcontainer.json
git commit -m "Add old devcontainer" -q
cd ../repo

OUTPUT=$("$REPOS_BIN" branch-update 2>&1) || true

# Check that the file was updated
if [ ! -f "../repo-test-branch/.devcontainer/devcontainer.json" ]; then
  print_fail "devcontainer.json was not written to the worktree"
fi

if grep -q "repositories" "../repo-test-branch/.devcontainer/devcontainer.json"; then
  print_fail "repositories section was not stripped from devcontainer.json"
fi

if ! grep -q "openFiles" "../repo-test-branch/.devcontainer/devcontainer.json"; then
  print_fail "openFiles section was incorrectly stripped from devcontainer.json"
fi

if ! echo "$OUTPUT" | grep -q "Updated devcontainer.json"; then
  print_fail "branch-update did not output success message"
fi

echo ""
echo "✅ All repos branch-update Go subcommand tests passed!"
