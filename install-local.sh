#!/usr/bin/env bash
# install-local.sh - Install repos CLI to a writable directory already in PATH

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

RELEASE_REPO="${REPOS_RELEASE_REPO:-miguelrodo/repos-go}"
BINARY_NAME="${REPOS_BINARY_NAME:-repos}"
DOWNLOAD_BASE_URL="https://github.com/${RELEASE_REPO}/releases/latest/download"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/repos"
STATE_FILE="${STATE_DIR}/install-dir"

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
  local dir probe_file
  IFS=':' read -r -a path_entries <<< "$PATH"
  for dir in "${path_entries[@]}"; do
    [ -n "$dir" ] || continue
    case "$dir" in
      /*) ;;
      *) continue ;;
    esac
    [ -d "$dir" ] || continue
    [ -x "$dir" ] || continue
    [ -w "$dir" ] || continue
    probe_file="$(mktemp "${dir}/.repos-write-test.XXXXXX" 2>/dev/null || true)"
    [ -n "$probe_file" ] || continue
    rm -f "$probe_file"
    echo "$dir"
    return 0
  done
  return 1
}

echo -e "${GREEN}Installing repos CLI...${NC}"
echo

if ! command -v curl >/dev/null 2>&1; then
  echo -e "${RED}Error: curl is required but not installed.${NC}" >&2
  exit 1
fi

sha256_tool=""
if command -v sha256sum >/dev/null 2>&1; then
  sha256_tool="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
  sha256_tool="shasum -a 256"
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
TMP_SUM="$(mktemp "${TMPDIR:-/tmp}/repos-install-sum.XXXXXX")"
trap 'rm -f "$TMP_BIN" "$TMP_SUM"' EXIT

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

if [ -n "$sha256_tool" ]; then
  if curl -fsSL "${DOWNLOAD_BASE_URL}/${DOWNLOADED_ASSET}.sha256" -o "$TMP_SUM"; then
    expected_sum="$(awk '{print $1}' "$TMP_SUM" | head -n 1)"
    if [ -z "$expected_sum" ]; then
      echo -e "${RED}Error: Downloaded checksum file was empty or invalid.${NC}" >&2
      exit 1
    fi
    actual_sum="$($sha256_tool "$TMP_BIN" | awk '{print $1}')"
    if [ "$expected_sum" != "$actual_sum" ]; then
      echo -e "${RED}Error: Checksum verification failed for ${DOWNLOADED_ASSET}.${NC}" >&2
      exit 1
    fi
  else
    echo "Warning: Checksum asset not found; skipping checksum verification."
  fi
fi

if command -v install >/dev/null 2>&1; then
  install -m 0755 "$TMP_BIN" "${INSTALL_DIR}/${BINARY_NAME}"
else
  cp "$TMP_BIN" "${INSTALL_DIR}/${BINARY_NAME}"
  chmod 0755 "${INSTALL_DIR}/${BINARY_NAME}"
fi

mkdir -p "$STATE_DIR"
printf '%s\n' "$INSTALL_DIR" > "$STATE_FILE"

echo
echo -e "${GREEN}✓ Installed ${BINARY_NAME} (${DOWNLOADED_ASSET}) to ${INSTALL_DIR}/${BINARY_NAME}${NC}"
echo "Run: ${BINARY_NAME} --help"
