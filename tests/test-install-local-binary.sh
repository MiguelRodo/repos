#!/usr/bin/env bash
# test-install-local-binary.sh - Verify binary download install flow

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

INSTALL_DIR="$TEST_DIR/install-bin"
MOCK_BIN="$TEST_DIR/mock-bin"
mkdir -p "$INSTALL_DIR" "$MOCK_BIN"

cat > "$MOCK_BIN/uname" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-s" ]; then
  echo "Linux"
elif [ "$1" = "-m" ]; then
  echo "x86_64"
else
  exit 1
fi
EOF
chmod +x "$MOCK_BIN/uname"

cat > "$MOCK_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
outfile=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      outfile="$2"
      shift 2
      ;;
    -f|-s|-S|-L)
      shift
      ;;
    *)
      url="$1"
      shift
      ;;
  esac
done

if [[ "$url" == *"/repos-linux-amd64" ]]; then
  cat > "$outfile" <<'BIN'
#!/usr/bin/env bash
echo "repos mock"
BIN
  exit 0
fi

exit 22
EOF
chmod +x "$MOCK_BIN/curl"

ORIGINAL_PATH="$PATH"
export PATH="$INSTALL_DIR:$MOCK_BIN:$ORIGINAL_PATH"
export REPOS_RELEASE_REPO="example/unused"

bash "$PROJECT_ROOT/install-local.sh"

if [ ! -x "$INSTALL_DIR/repos" ]; then
  echo "FAIL: repos binary was not installed to first writable PATH directory"
  exit 1
fi

if [ "$("$INSTALL_DIR/repos")" != "repos mock" ]; then
  echo "FAIL: installed repos binary did not execute expected output"
  exit 1
fi

bash "$PROJECT_ROOT/uninstall-local.sh"

if [ -f "$INSTALL_DIR/repos" ]; then
  echo "FAIL: uninstall-local.sh did not remove installed binary"
  exit 1
fi

echo "PASS: install-local.sh installs release binary into writable PATH directory"
