#!/usr/bin/env bash
# tests/test-branch-hardening.sh — Verify branch name validation hardening
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLONE_SCRIPT="$PROJECT_ROOT/scripts/helper/clone-repos.sh"

# Create a temporary directory for the test
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

cd "$TEST_DIR"
mkdir -p repo
cd repo
git init -q
git commit -q --allow-empty -m "Initial commit"
git remote add origin https://github.com/owner/repo
REPOS_LIST="$TEST_DIR/repos.list"

echo "Testing malicious branch names..."

malicious_branches=("" "-h" "--help" "../traversal")

for branch in "${malicious_branches[@]}"; do
  echo "Testing branch: '$branch'"
  echo "@$branch" > "$REPOS_LIST"

  # We use a subshell to avoid authentication errors killing the script if it gets that far
  # but here we expect it to fail early due to our new validation
  OUTPUT=$(bash "$CLONE_SCRIPT" -f "$REPOS_LIST" 2>&1) || true

  if echo "$OUTPUT" | grep -q "is not a valid Git branch name"; then
    echo "  ✓ Correcty rejected: '$branch'"
  else
    echo "  ❌ FAILED: Malicious branch '$branch' was NOT rejected!"
    echo "  Output: $OUTPUT"
    exit 1
  fi
done

echo "Test script finished."
