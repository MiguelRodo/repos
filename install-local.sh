#!/usr/bin/env bash
# install-local.sh - Install repos CLI to a writable directory already in PATH

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

RELEASE_REPO="${REPOS_RELEASE_REPO:-miguelrodo/repos-go}"
BINARY_NAME="${REPOS_BINARY_NAME:-repos}"
DOWNLOAD_BASE_URL="https://github.com/${RELEASE_REPO}/releases/latest/download"

map_os() {
  case "$(uname -s)" in
    Linux) echo "linux" ;;
    Darwin) echo "darwin" ;;
    *)
      echo -e "${RED}Error: Unsupported OS: $(uname -s)${NC}" >&2
      exit 1
      ;;
  esac
}

map_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    arm64|aarch64) echo "arm64" ;;
    *)
      echo -e "${RED}Error: Unsupported architecture: $(uname -m)${NC}" >&2
      exit 1
      ;;
  esac
}

find_writable_path_dir() {
  local dir
  IFS=':' read -r -a path_entries <<< "$PATH"
  for dir in "${path_entries[@]}"; do
    [ -n "$dir" ] || continue
    if [ -d "$dir" ] && [ -w "$dir" ]; then
      echo "$dir"
      return 0
    fi
  done
  return 1
}

echo -e "${GREEN}Installing repos CLI...${NC}"
echo

if ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}Error: curl is required but not installed.${NC}" >&2
  exit 1
fi

OS_NAME="$(map_os)"
ARCH_NAME="$(map_arch)"

if ! INSTALL_DIR="$(find_writable_path_dir)"; then
  echo -e "${RED}Error: No writable directory found in PATH.${NC}" >&2
  echo "Please create a writable directory in PATH and run the installer again." >&2
  exit 1
fi

echo "Detected platform: ${OS_NAME}/${ARCH_NAME}"
echo "Install directory: ${INSTALL_DIR}"

ASSET_CANDIDATES=(
  "${BINARY_NAME}-${OS_NAME}-${ARCH_NAME}"
  "${BINARY_NAME}_${OS_NAME}_${ARCH_NAME}"
)

TMP_BIN="$(mktemp "${TMPDIR:-/tmp}/repos-install.XXXXXX")"
trap 'rm -f "$TMP_BIN"' EXIT

DOWNLOADED_ASSET=""
for asset in "${ASSET_CANDIDATES[@]}"; do
  url="${DOWNLOAD_BASE_URL}/${asset}"
  echo "Trying ${url}..."
  if curl -fsSL "$url" -o "$TMP_BIN"; then
    DOWNLOADED_ASSET="$asset"
    break
  fi
done

if [ -z "$DOWNLOADED_ASSET" ]; then
  echo -e "${RED}Error: Could not download a release asset for ${OS_NAME}/${ARCH_NAME}.${NC}" >&2
  echo "Tried: ${ASSET_CANDIDATES[*]}" >&2
  echo "From: ${DOWNLOAD_BASE_URL}" >&2
  exit 1
fi

install -m 0755 "$TMP_BIN" "${INSTALL_DIR}/${BINARY_NAME}"

echo
echo -e "${GREEN}✓ Installed ${BINARY_NAME} (${DOWNLOADED_ASSET}) to ${INSTALL_DIR}/${BINARY_NAME}${NC}"
echo "Run: ${BINARY_NAME} --help"
