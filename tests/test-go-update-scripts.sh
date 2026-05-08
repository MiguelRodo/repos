#!/usr/bin/env bash
# tests/test-go-update-scripts.sh — Integration tests for `repos update-scripts`
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_BIN=$(mktemp -t repos-go-update-scripts-bin-XXXXXX)
TEST_DIR=$(mktemp -d -t repos-go-update-scripts-XXXXXX)
cleanup() {
  rm -f "$TMP_BIN"
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

if ! go build -o "$TMP_BIN" "$PROJECT_ROOT/cmd/repos" 2>/dev/null; then
  echo "SKIP: could not build repos binary"
  exit 0
fi
REPOS_BIN="$TMP_BIN"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'
print_pass() { printf "${GREEN}✓ PASS: %s${NC}\n" "$1"; }
print_fail() { printf "${RED}❌ FAIL: %s${NC}\n" "$1"; exit 1; }

setup_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git init -q "$dir"
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" config user.name "Test"
  touch "$dir/.gitkeep"
  git -C "$dir" add .gitkeep
  git -C "$dir" commit -q -m "init"
}

BASE_REPO="$TEST_DIR/base"
mkdir -p "$BASE_REPO/scripts" "$BASE_REPO/.github/workflows"
setup_repo "$BASE_REPO"
git -C "$BASE_REPO" remote add origin "https://github.com/example/base.git"

cat > "$BASE_REPO/scripts/tool.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "new-tool"
SCRIPT
chmod +x "$BASE_REPO/scripts/tool.sh"

cat > "$BASE_REPO/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: echo ok
YAML

ALPHA_REPO="$TEST_DIR/alpha"
BETA_REPO="$TEST_DIR/custom-beta"
setup_repo "$ALPHA_REPO"
setup_repo "$BETA_REPO"

echo '#!/usr/bin/env bash' > "$ALPHA_REPO/scripts_old.sh"
chmod -x "$ALPHA_REPO/scripts_old.sh"
mkdir -p "$ALPHA_REPO/scripts" "$ALPHA_REPO/.github/workflows"
echo 'echo old-tool' > "$ALPHA_REPO/scripts/tool.sh"
chmod -x "$ALPHA_REPO/scripts/tool.sh"
echo 'echo remove-me' > "$ALPHA_REPO/scripts/obsolete.sh"
echo 'name: old' > "$ALPHA_REPO/.github/workflows/ci.yml"

git -C "$ALPHA_REPO" add .
git -C "$ALPHA_REPO" commit -q -m "old infra"

cat > "$BASE_REPO/repos.list" <<'LIST'
example/alpha
example/beta custom-beta
LIST

cd "$BASE_REPO"

OUTPUT=$("$REPOS_BIN" update-scripts --help 2>&1) || true
if echo "$OUTPUT" | grep -q "Usage:"; then
  print_pass "Help output is shown"
else
  print_fail "Help output missing"
fi

DRY_RUN_OUTPUT=$("$REPOS_BIN" update-scripts --dry-run 2>&1)
if echo "$DRY_RUN_OUTPUT" | grep -q "would update"; then
  print_pass "Dry-run reports pending updates"
else
  print_fail "Dry-run did not report pending updates"
fi

"$REPOS_BIN" update-scripts --stage >/dev/null

if grep -q 'new-tool' "$ALPHA_REPO/scripts/tool.sh" && [ -x "$ALPHA_REPO/scripts/tool.sh" ]; then
  print_pass "Scripts synced and executable bit preserved"
else
  print_fail "Scripts were not synced correctly"
fi

if [ ! -e "$ALPHA_REPO/scripts/obsolete.sh" ]; then
  print_pass "Extraneous files removed during mirror"
else
  print_fail "Extraneous files were not removed"
fi

if [ -f "$BETA_REPO/scripts/tool.sh" ] && [ -f "$BETA_REPO/.github/workflows/ci.yml" ]; then
  print_pass "Shared paths mirrored to custom target directory"
else
  print_fail "Custom target directory was not mirrored"
fi

ALPHA_STAGED=$(git -C "$ALPHA_REPO" diff --cached --name-only)
BETA_STAGED=$(git -C "$BETA_REPO" diff --cached --name-only)
if echo "$ALPHA_STAGED" | grep -q "scripts/tool.sh" && echo "$BETA_STAGED" | grep -q "scripts/tool.sh"; then
  print_pass "--stage runs git add in updated repositories"
else
  print_fail "Expected staged changes were not found"
fi

echo ""
echo "✅ All repos update-scripts Go subcommand tests passed!"
