#!/usr/bin/env bash
# install-local.sh - Install repos to user's local directory without sudo
# This script installs repos to ~/.local/bin and ~/.local/share/repos

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Installation directories
LOCAL_BIN="$HOME/.local/bin"
LOCAL_SHARE="$HOME/.local/share/repos"

# Script directory (where this install script is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Installing repos to user's local directory...${NC}"
echo

# Check for required dependencies
echo "Checking dependencies..."
MISSING_DEPS=()
for dep in bash git curl jq; do
    if ! command -v "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${RED}Error: Missing required dependencies: ${MISSING_DEPS[*]}${NC}"
    echo "Please install them using:"
    echo "  sudo apt-get install ${MISSING_DEPS[*]}"
    echo "or equivalent for your system."
    exit 1
fi
echo -e "${GREEN}✓ All dependencies are installed${NC}"
echo

# Create installation directories
echo "Creating installation directories..."
mkdir -p "$LOCAL_BIN"
mkdir -p "$LOCAL_SHARE"
echo -e "${GREEN}✓ Created directories${NC}"
echo

# Copy scripts to local share directory
echo "Installing scripts to $LOCAL_SHARE..."
cp -r "$SCRIPT_DIR/scripts" "$LOCAL_SHARE/"

# Make all shell scripts executable
find "$LOCAL_SHARE/scripts" -type f -name "*.sh" -exec chmod +x {} \;
echo -e "${GREEN}✓ Scripts installed${NC}"
echo

# Create wrapper script in local bin
echo "Creating repos command in $LOCAL_BIN..."
cat > "$LOCAL_BIN/repos" << 'WRAPPER_EOF'
#!/usr/bin/env bash
# repos - Multi-repository management tool wrapper
# This script launches setup-repos.sh from the installed location

set -euo pipefail

SCRIPT_DIR="$HOME/.local/share/repos/scripts"
SETUP_SCRIPT="$SCRIPT_DIR/setup-repos.sh"

if [ ! -f "$SETUP_SCRIPT" ]; then
  echo "Error: setup-repos.sh not found at $SETUP_SCRIPT" >&2
  echo "The repos package may not be installed correctly." >&2
  exit 1
fi

# Execute setup-repos.sh with all passed arguments
exec "$SETUP_SCRIPT" "$@"
WRAPPER_EOF

chmod +x "$LOCAL_BIN/repos"
echo -e "${GREEN}✓ repos command installed${NC}"
echo

# Check if ~/.local/bin is in PATH
echo "Checking PATH configuration..."
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    echo -e "${YELLOW}Warning: $LOCAL_BIN is not in your PATH${NC}"
    echo
    echo "Add the following line to your ~/.bashrc or ~/.profile:"
    echo
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo
    echo "Then reload your shell configuration:"
    echo "  source ~/.bashrc"
    echo
    echo "Or start a new terminal session."
else
    echo -e "${GREEN}✓ $LOCAL_BIN is already in PATH${NC}"
fi
echo

echo -e "${GREEN}Installation complete!${NC}"
echo
echo "You can now use the repos command:"
echo "  repos --help"
echo
echo "Additional scripts are available in:"
echo "  $LOCAL_SHARE/scripts/"
echo
echo "To uninstall, run:"
echo "  bash $SCRIPT_DIR/uninstall-local.sh"
echo
