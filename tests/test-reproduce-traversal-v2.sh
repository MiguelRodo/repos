#!/usr/bin/env bash
set -euo pipefail

# Setup
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# Get absolute path to project root before we start changing directories
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Copy script to $TEST_DIR/bin/
mkdir -p "$TEST_DIR/bin"
cp "$PROJECT_ROOT/scripts/run-pipeline.sh" "$TEST_DIR/bin/"
mkdir -p "$TEST_DIR/scripts"
mkdir -p "$TEST_DIR/scripts/helper"
cp "$PROJECT_ROOT/scripts/helper/install-r-deps.sh" "$TEST_DIR/scripts/helper/"

cd "$TEST_DIR"
git init -q
git config user.email "you@example.com"
git config user.name "Your Name"
git add .
git commit -m "initial" -q

# Create repos.list here in PROJECT_ROOT
cat > repos.list <<EOF
owner/repo
EOF

# Create a malicious workspace file
cat > entire-project.code-workspace <<EOF
{
  "folders": [
    {"path": "."},
    {"path": ".."},
    {"path": "repo/.."},
    {"path": "../repo"},
    {"path": "../repo/.."}
  ]
}
EOF

# Ensure the script is executable
chmod +x ./bin/run-pipeline.sh

echo "Running run-pipeline.sh with malicious workspace..."
./bin/run-pipeline.sh -v --script "i-do-not-exist.sh" --continue-on-error > output.log 2>&1 || true

cat output.log

# Check that malicious paths were rejected
# and that the legitimate path "." and "../repo" were processed.

# Rejected:
# ..
# repo/..
# ../repo/..

# Accepted:
# . (skipped because it's current dir, but reaches run_in_repo)
# ../repo

echo "--- VALIDATION RESULTS ---"
if grep -q "Error: invalid workspace folder path (unauthorized '..', absolute, or leading hyphen): .." output.log; then
    echo "PASS: rejected '..'"
else
    echo "FAIL: did not reject '..'"
    exit 1
fi

if grep -q "Error: invalid workspace folder path (unauthorized '..', absolute, or leading hyphen): repo/.." output.log; then
    echo "PASS: rejected 'repo/..'"
else
    echo "FAIL: did not reject 'repo/..'"
    exit 1
fi

if grep -q "Error: invalid workspace folder path (unauthorized '..', absolute, or leading hyphen): ../repo/.." output.log; then
    echo "PASS: rejected '../repo/..'"
else
    echo "FAIL: did not reject '../repo/..'"
    exit 1
fi

if grep -q "⏵ repo: i-do-not-exist.sh found" output.log || grep -q "⏭ repo: no i-do-not-exist.sh" output.log || grep -q "⚠️  Folder not found: /tmp/.*/repo" output.log; then
    echo "PASS: processed '../repo'"
else
    echo "FAIL: did not process '../repo'"
    exit 1
fi

echo "VERIFICATION SUCCESSFUL"
