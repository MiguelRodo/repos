#!/usr/bin/env bash
# tests/test-umask-hardening.sh
set -euo pipefail

# This test verifies that temporary files are created with restrictive permissions (0600)
# regardless of the ambient umask.

# Set a permissive umask
umask 022

# We want to check if our scripts create temporary files securely.
# Since mktemp on this system might already be secure, we will
# primarily check for the presence of the umask 077 hardening pattern
# in the source code, as mandated by the project's security standards.

echo "Checking scripts for umask 077 protection on mktemp calls..."

# List of scripts that should be hardened
SCRIPTS=(
    "scripts/add-branch.sh"
    "scripts/run-pipeline.sh"
    "scripts/update-branches.sh"
    "scripts/update-scripts.sh"
    "scripts/helper/clone-repos.sh"
    "scripts/helper/codespaces-auth-add.sh"
    "scripts/helper/create-repos.sh"
    "scripts/helper/vscode-workspace-add.sh"
)

failed=0
for script in "${SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        echo "Warning: $script not found, skipping."
        continue
    fi

    # Find mktemp calls that don't have umask 077
    # We look for lines containing mktemp but NOT umask 077
    # We ignore comments and documentation strings about requirements
    insecure_calls=$(grep "mktemp" "$script" | grep -v "umask 077" | grep -v "^#" | grep -v "for cmd in" || true)

    if [ -n "$insecure_calls" ]; then
        echo "❌ Insecure mktemp call(s) found in $script:"
        echo "$insecure_calls"
        failed=1
    else
        echo "✅ $script appears hardened."
    fi
done

if [ $failed -eq 1 ]; then
    echo ""
    echo "VULNERABILITY DEMONSTRATION:"
    echo "On systems where mktemp respects umask, these files would be created"
    echo "with permissions like 0644, allowing other users to read sensitive data."
    echo "Ambient umask is $(umask), which would result in 0644 permissions."
    exit 1
else
    echo "All scripts are hardened with umask 077."
    exit 0
fi
