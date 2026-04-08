#!/usr/bin/env bash
# tests/test-create-repos-enhancements.sh
# Verifies URL encoding and fix for 'local' bug in create-repos.sh

set -Eeuo pipefail

# --- Setup ---
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

REPO_ROOT=$(pwd)
CREATE_SCRIPT="$REPO_ROOT/scripts/helper/create-repos.sh"

cd -- "$TEST_DIR"

# Mock curl to log URLs and return dummy JSON or HTTP code
cat > mock-curl <<'EOF'
#!/usr/bin/env bash
URL=""
WANT_CODE=0
for arg in "$@"; do
    if [[ "$arg" == http* ]]; then URL="$arg"; fi
    if [[ "$arg" == "%{http_code}" ]]; then WANT_CODE=1; fi
done
[ -n "$URL" ] && echo "$URL" >> curl_calls.log

if [ "$WANT_CODE" -eq 1 ]; then
    if [[ "$URL" == *"users/owner.name" ]]; then echo "200"; exit 0; fi
    if [[ "$URL" == *"repos/owner.name/repo.name/git/refs/heads/branch%2Fwith%2Fslash" ]]; then echo "404"; exit 0; fi
    if [[ "$URL" == *"repos/owner.name/repo.name" ]]; then echo "200"; exit 0; fi
    if [[ "$URL" == *"user" ]]; then echo "200"; exit 0; fi
    echo "404"
    exit 0
fi

# Return dummy JSON based on the URL
if [[ "$URL" == *"users/owner.name" ]]; then
    echo '{"type": "User", "login": "owner.name"}'
elif [[ "$URL" == *"repos/owner.name/repo.name" ]]; then
    echo '{"name": "repo.name"}'
elif [[ "$URL" == *"user" ]]; then
    echo '{"login": "test-user"}'
else
    echo '{"message": "Not Found"}'
fi
exit 0
EOF
chmod +x mock-curl
export PATH="$TEST_DIR:$PATH"
# Use a script on PATH instead of a function, more reliable for subshells
cp mock-curl curl

# Mock git
cat > mock-git <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == "rev-parse --is-inside-work-tree" ]]; then
    exit 1 # Not in a git repo for this test
fi
exit 0
EOF
chmod +x mock-git
export PATH=".:$PATH"

# Create repos.list with special characters
# Use characters that are valid in components but might need encoding
# NOTE: repo_path validation regex `^[^/]+/[^/]+$` prevents multiple slashes in owner/repo
# So we use characters like # or dots or just one slash between owner and repo.
# For owner and repo names, they are validated with `^[a-zA-Z0-9][a-zA-Z0-9._-]*$`
# So we can't really have slashes IN owner or repo names according to the script's validation.
# However, branch names CAN have slashes and are validated with `git check-ref-format`.
cat > repos.list <<'EOF'
owner.name/repo.name@branch/with/slash
EOF

# --- Run Test ---
echo "Running create-repos.sh with special characters..."
export GH_TOKEN="dummy_token"
export GH_USER="dummy_user"

# Run the script. We use 'bash' to run it to ensure the mock PATH is used
# and we don't rely on the shebang if it might bypass our mock.
# Actually, the script uses #!/usr/bin/env bash, so PATH mock should work.
# We also want to check for stderr for the 'local' bug warning.
bash "$CREATE_SCRIPT" -f repos.list > output.log 2> error.log || {
    echo "FAILED: create-repos.sh exited with error"
    cat error.log
    exit 1
}

# --- Verification ---

# 1. Check for 'local' bug warning in stderr
if grep -q "local: can only be used in a function" error.log; then
    echo "FAILED: 'local' keyword error found in stderr"
    cat error.log
    exit 1
else
    echo "PASSED: No 'local' keyword error found."
fi

# 2. Check curl calls for URL encoding
# owner-with/slash -> owner-with%2Fslash
# repo-with#hash -> repo-with%23hash
# branch-with/slash -> branch-with%2Fslash

echo "Verifying URL encoding in API calls..."
if [ ! -f curl_calls.log ]; then
    echo "FAILED: No curl calls logged"
    exit 1
fi

# Expected URLs (normalised to what we expect mock-curl to receive)
EXPECTED_USER_URL="https://api.github.com/users/owner.name"
EXPECTED_REPO_URL="https://api.github.com/repos/owner.name/repo.name"
EXPECTED_BRANCH_URL="https://api.github.com/repos/owner.name/repo.name/git/refs/heads/branch%2Fwith%2Fslash"

# Check each expected URL in the log
for url in "$EXPECTED_USER_URL" "$EXPECTED_REPO_URL" "$EXPECTED_BRANCH_URL"; do
    if grep -qF "$url" curl_calls.log; then
        echo "PASSED: Found encoded URL: $url"
    else
        echo "FAILED: Encoded URL not found in log: $url"
        echo "Actual calls:"
        cat curl_calls.log
        exit 1
    fi
done

echo "✅ All enhancement tests passed!"
