#!/usr/bin/env bash
# uninstall-local.sh - Uninstall repos from user's local directory

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Installation directories
LOCAL_BIN="$HOME/.local/bin"
LOCAL_SHARE="$HOME/.local/share/repos"

echo -e "${YELLOW}Uninstalling repos from user's local directory...${NC}"
echo

# Remove the repos command
if [ -f "$LOCAL_BIN/repos" ]; then
    echo "Removing repos command from $LOCAL_BIN..."
    rm "$LOCAL_BIN/repos"
    echo -e "${GREEN}✓ Removed repos command${NC}"
else
    echo -e "${YELLOW}repos command not found in $LOCAL_BIN${NC}"
fi
echo

# Remove the scripts directory
if [ -d "$LOCAL_SHARE" ]; then
    echo "Removing scripts from $LOCAL_SHARE..."
    rm -rf "$LOCAL_SHARE"
    echo -e "${GREEN}✓ Removed scripts directory${NC}"
else
    echo -e "${YELLOW}Scripts directory not found at $LOCAL_SHARE${NC}"
fi
echo

echo -e "${GREEN}Uninstallation complete!${NC}"
echo
