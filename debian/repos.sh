#!/usr/bin/env bash
# repos - Multi-repository management tool wrapper
# This script launches setup-repos.sh from the installed location

set -euo pipefail

SCRIPT_DIR="/usr/share/repos/scripts"
SETUP_SCRIPT="$SCRIPT_DIR/setup-repos.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
  echo "Error: setup-repos.sh not found at $SETUP_SCRIPT" >&2
  echo "The repos package may not be installed correctly." >&2
  exit 1
fi

# Execute setup-repos.sh with all passed arguments
exec "$SETUP_SCRIPT" "$@"
