#!/usr/bin/env bash
# uninstall-local.sh - Uninstall repos from writable PATH directories

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Uninstalling repos from PATH directories...${NC}"
echo

REMOVED_ANY=0
IFS=':' read -r -a path_entries <<< "$PATH"
for dir in "${path_entries[@]}"; do
    [ -n "$dir" ] || continue
    if [ -f "$dir/repos" ]; then
        echo "Removing $dir/repos..."
        rm -f "$dir/repos"
        echo -e "${GREEN}✓ Removed $dir/repos${NC}"
        REMOVED_ANY=1
    fi
done

if [ "$REMOVED_ANY" -eq 0 ]; then
    echo -e "${YELLOW}No repos binary found in PATH directories.${NC}"
fi

echo -e "${GREEN}Uninstallation complete!${NC}"
echo
