#!/usr/bin/env bash
set -euo pipefail

# test-credential-leak-sentinel.sh
# Verifies that credentials in URLs are NOT leaked to stdout/stderr

SCRIPT_DIR="$(cd "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

cd "$TEST_DIR"
git init -q base-repo
cd base-repo
git remote add origin https://github.com/example/main
touch repos.list

# Scenario 1: clone-repos.sh
# Note: we use grep -F to avoid issues with special characters in the token if we had any
TOKEN="my-secret-token"
echo "https://${TOKEN}@github.com/owner/repo@branch" > repos.list
printf "Testing clone-repos.sh...\n"
# We expect it to fail because the URL is fake, but we check if the token is leaked in the output
OUTPUT=$(GH_TOKEN=fake bash "$REPO_ROOT/scripts/helper/clone-repos.sh" -f repos.list 2>&1 || true)
if echo "$OUTPUT" | grep -F "$TOKEN"; then
  printf "❌ FAIL: clone-repos.sh leaked credentials!\n"
  echo "Output was:"
  echo "$OUTPUT"
  exit 1
else
  printf "✅ PASS: clone-repos.sh did not leak credentials.\n"
fi

# Scenario 2: create-repos.sh
TOKEN2="another-secret-token"
export GH_USER=fake
export GH_TOKEN=some-token
echo "https://${TOKEN2}@github.com/owner/repo" > repos.list
printf "Testing create-repos.sh...\n"
OUTPUT2=$(bash "$REPO_ROOT/scripts/helper/create-repos.sh" -f repos.list --debug 2>&1 || true)
if echo "$OUTPUT2" | grep -F "$TOKEN2"; then
  printf "❌ FAIL: create-repos.sh leaked credentials!\n"
  echo "Output was:"
  echo "$OUTPUT2"
  exit 1
else
  printf "✅ PASS: create-repos.sh did not leak credentials.\n"
fi

printf "\nALL TESTS PASSED\n"
