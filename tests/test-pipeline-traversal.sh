#!/usr/bin/env bash
# tests/test-pipeline-traversal.sh - Reproduce path traversal in run-pipeline.sh

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

print_pass() { echo -e "${GREEN}PASS: $1${NC}"; }
print_fail() { echo -e "${RED}FAIL: $1${NC}"; exit 1; }

# Create a workspace for testing
TEST_DIR=$(mktemp -d)
# Ensure cleanup on exit
trap 'rm -rf "$TEST_DIR" /tmp/malicious_pipeline.sh /tmp/pipeline_exploited' EXIT

# 1. Create malicious script outside TEST_DIR
cat > /tmp/malicious_pipeline.sh <<'EOF'
#!/bin/bash
touch /tmp/pipeline_exploited
echo "PIPELINE EXPLOITED"
EOF
chmod +x /tmp/malicious_pipeline.sh

# 2. Setup dummy repo and workspace
mkdir -p "$TEST_DIR/project/dummy-repo"
cd "$TEST_DIR/project"

# Copy the script to be tested
mkdir -p scripts
cp "$OLDPWD/scripts/run-pipeline.sh" scripts/

cat > entire-project.code-workspace <<'EOF'
{
  "folders": [
    { "path": "dummy-repo" }
  ]
}
EOF

# Test Case 1: Path traversal via --script flag
echo "Testing Case 1: --script flag traversal..."
rm -f /tmp/pipeline_exploited
# Use enough .. to reach /tmp/malicious_pipeline.sh from dummy-repo
./scripts/run-pipeline.sh --script ../../../../../../../../../../../../../../../../../tmp/malicious_pipeline.sh || true

if [ -f /tmp/pipeline_exploited ]; then
  print_fail "Vulnerability reproduced: --script flag allowed path traversal!"
else
  # If it didn't exploit, it might be because the path was wrong, or it was prevented.
  # But we saw it work in the main session.
  print_pass "--script flag path traversal prevented (or script not found)."
fi

# Test Case 2: Path traversal via concise repo list
echo "Testing Case 2: Concise repo list traversal..."
rm -f /tmp/pipeline_exploited
cat > concise.list <<'EOF'
dummy-repo ../../../../../../../../../../../../../../../../../tmp/malicious_pipeline.sh
EOF

./scripts/run-pipeline.sh -f concise.list || true

if [ -f /tmp/pipeline_exploited ]; then
  print_fail "Vulnerability reproduced: concise repo list allowed path traversal!"
else
  print_pass "Concise repo list path traversal prevented."
fi

print_pass "Test complete."
