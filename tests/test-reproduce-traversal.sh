#!/usr/bin/env bash
set -Eeo pipefail

# Test reproduction of path traversal in clone-repos.sh planning phase

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CLONE_SCRIPT="$REPO_ROOT/scripts/helper/clone-repos.sh"

# Create temp workspace
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# echo "Temp workspace: $TEMP_DIR"

cd "$TEMP_DIR"
mkdir -p work/main-repo
cd work/main-repo
git init
git config user.email "test@example.com"
git config user.name "Test User"
touch a && git add a && git commit -m "initial"
git remote add origin https://github.com/owner/main-repo
cd ..

# Create another repo to be the target of traversal
mkdir -p remote/other-repo
cd remote/other-repo
git init
git config user.email "test@example.com"
git config user.name "Test User"
touch b && git add b && git commit -m "initial"
OTHER_REPO_PATH="$(pwd)"
cd ../..

# Now we are in $TEMP_DIR/work
cd main-repo

# Create malicious repos.list
# Line 1: Populates plan for other-repo with traversal. Fails in execution.
# Line 2: Single-branch clone for other-repo.
#         Triggers base priming because ref_count > 1.
cat > repos.list <<EOF
file://$OTHER_REPO_PATH ../traversal
file://$OTHER_REPO_PATH@master
EOF

# echo "Running clone-repos.sh..."
# We suppress output but allow it to run
bash "$CLONE_SCRIPT" > /dev/null 2>&1 || true

# The parent directory of work/main-repo is work.
# work/../traversal is just traversal.
if [ -d "$TEMP_DIR/traversal" ]; then
  echo "❌ VULNERABILITY DETECTED: Base repo created in traversed location: $TEMP_DIR/traversal"
  exit 1
else
  echo "✅ Path traversal not detected in $TEMP_DIR/traversal"
  exit 0
fi
