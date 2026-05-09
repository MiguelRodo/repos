#!/usr/bin/env bash
# uninstall-local.sh - Uninstall repos from writable PATH directories

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/repos"
STATE_FILE="${STATE_DIR}/install-dir"

echo -e "${YELLOW}Uninstalling repos from PATH directories...${NC}"
echo

REMOVED_ANY=0
TARGET_DIR=""
if [ -f "$STATE_FILE" ]; then
    TARGET_DIR="$(head -n 1 "$STATE_FILE")"
fi

case "$TARGET_DIR" in
    /*) ;;
    *) TARGET_DIR="" ;;
esac

if [ -n "$TARGET_DIR" ] && [ -f "$TARGET_DIR/repos" ]; then
    echo "Removing $TARGET_DIR/repos..."
    if rm -f "$TARGET_DIR/repos"; then
        echo -e "${GREEN}✓ Removed $TARGET_DIR/repos${NC}"
        REMOVED_ANY=1
    else
        echo -e "${YELLOW}Warning: Could not remove $TARGET_DIR/repos${NC}"
    fi
fi

if [ "$REMOVED_ANY" -eq 0 ]; then
    echo -e "${YELLOW}No repos binary found at recorded install location.${NC}"
fi

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE" || true
fi

echo -e "${GREEN}Uninstallation complete!${NC}"
echo
