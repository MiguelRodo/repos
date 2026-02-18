#!/usr/bin/env bash
# setup-repos.sh — orchestrate project bootstrapping
# Requires: bash 3.2+, curl, git, and helper scripts

set -euo pipefail

# — Debug support —
DEBUG=false
DEBUG_FILE=""
DEBUG_FD=3  # Use FD 3 for debug output (compatible with Bash 3.2+)

debug() {
  if $DEBUG; then
    echo "[DEBUG] $*" >&$DEBUG_FD
  fi
}

# Get platform-independent temp directory
get_temp_dir() {
  # Try various temp directory variables in order of preference
  if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR}" ]; then
    echo "${TMPDIR%/}"  # Remove trailing slash if present
  elif [ -n "${TEMP:-}" ] && [ -d "${TEMP}" ]; then
    echo "${TEMP%/}"
  elif [ -n "${TMP:-}" ] && [ -d "${TMP}" ]; then
    echo "${TMP%/}"
  elif [ -d "/tmp" ]; then
    echo "/tmp"
  else
    # Fallback to current directory
    echo "."
  fi
}

# — Paths & defaults —
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Detect if we're running from an installed package location
# If so, use current working directory for repos.list lookup
if [[ "$SCRIPT_DIR" == */usr/share/repos/scripts ]]; then
  # Running from installed package - use current working directory
  REPOS_SEARCH_DIR="$PWD"
else
  # Running from source - use project root
  REPOS_SEARCH_DIR="$PROJECT_ROOT"
fi

if [ ! -f "$REPOS_SEARCH_DIR/repos.list" ] && [ -f "$REPOS_SEARCH_DIR/repos-to-clone.list" ]; then
  REPOS_FILE="$REPOS_SEARCH_DIR/repos-to-clone.list"
else
  REPOS_FILE="$REPOS_SEARCH_DIR/repos.list"
fi

PUBLIC_FLAG=false
PERMISSIONS_OPT=""
TOOL_OPT=""
CODESPACES_FLAG=false
DEVCONTAINER_PATHS=()

CODESPACES_SCRIPT="$SCRIPT_DIR/helper/codespaces-auth-add.sh"
CREATE_SCRIPT="$SCRIPT_DIR/helper/create-repos.sh"
CLONE_SCRIPT="$SCRIPT_DIR/helper/clone-repos.sh"
WORKSPACE_SCRIPT="$SCRIPT_DIR/helper/vscode-workspace-add.sh"

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -f, --file <file>             Use <file> instead of repos.list
  -p, --public                  Create repos as public (default is private)
  --codespaces                  Enable Codespaces authentication configuration
  -d, --devcontainer <path>     Path to devcontainer.json (can be specified multiple times)
                                Implies --codespaces
  --permissions <all|contents>  Pass through to codespaces-auth-add.sh
  -t, --tool <jq|python|…>      Force tool for codespaces-auth-add.sh
  --debug                       Enable debug output to stderr
  --debug-file [file]           Enable debug output to file (auto-generated if not specified)
  -h, --help                    Show this help and exit
EOF
  exit "${1:-1}"
}

# — Parse args —
while [ $# -gt 0 ]; do
  case $1 in
    -f|--file)      shift; [ $# -gt 0 ] || usage; REPOS_FILE="$1"; shift ;;
    -p|--public)    PUBLIC_FLAG=true; shift ;;
    --codespaces)   CODESPACES_FLAG=true; shift ;;
    -d|--devcontainer)
      shift; [ $# -gt 0 ] || usage
      DEVCONTAINER_PATHS+=("$1")
      CODESPACES_FLAG=true
      shift
      ;;
    --permissions)  shift; [ $# -gt 0 ] || usage; PERMISSIONS_OPT="$1"; shift ;;
    -t|--tool)      shift; [ $# -gt 0 ] || usage; TOOL_OPT="$1"; shift ;;
    --debug)        DEBUG=true; shift ;;
    --debug-file)   
      DEBUG=true
      shift
      # Check if next arg exists and is not a flag
      if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
        DEBUG_FILE="$1"
        shift
      else
        # Auto-generate debug file in platform-independent temp directory
        TEMP_DIR=$(get_temp_dir)
        DEBUG_FILE="${TEMP_DIR}/repos-debug-$(date +%Y%m%d-%H%M%S)-$$.log"
      fi
      ;;
    -h|--help)      usage 0 ;;
    *)              echo "Unknown option: $1" >&2; usage ;;
  esac
done

# Set up debug file descriptor if needed
if [ -n "$DEBUG_FILE" ]; then
  exec 3>>"$DEBUG_FILE"
  echo "Debug output will be written to: $DEBUG_FILE" >&2
else
  # Redirect FD 3 to stderr by default
  exec 3>&2
fi

debug "=== Setup-repos.sh Debug Session Started ==="
debug "Script directory: $SCRIPT_DIR"
debug "Project root: $PROJECT_ROOT"
debug "Repos search dir: $REPOS_SEARCH_DIR"
debug "Repos file: $REPOS_FILE"
debug "Public flag: $PUBLIC_FLAG"
debug "Debug enabled: $DEBUG"
debug "Debug file: ${DEBUG_FILE:-none}"

[ -f "$REPOS_FILE" ] || { echo "Error: repo list '$REPOS_FILE' not found." >&2; exit 1; }

debug "Repos file exists: $REPOS_FILE"

# — Ensure helpers exist —
for script in "$CREATE_SCRIPT" "$CLONE_SCRIPT" "$WORKSPACE_SCRIPT"; do
  [ -x "$script" ] || { echo "Error: '$script' not found or not executable." >&2; exit 1; }
  debug "Helper script found: $script"
done

# Prepare debug flags to pass to helper scripts
DEBUG_ARGS=()
if $DEBUG; then
  DEBUG_ARGS+=( --debug )
  if [ -n "$DEBUG_FILE" ]; then
    DEBUG_ARGS+=( --debug-file "$DEBUG_FILE" )
  fi
fi

debug "Debug args to pass to helpers: ${DEBUG_ARGS[*]}"

echo "=== 1) Creating repos ==="
debug "Running create-repos.sh with args: -f $REPOS_FILE $PUBLIC_FLAG ${DEBUG_ARGS[*]}"
create_args=( -f "$REPOS_FILE" )
$PUBLIC_FLAG && create_args+=( --public )
create_args+=( "${DEBUG_ARGS[@]}" )
"$CREATE_SCRIPT" "${create_args[@]}"

echo "=== 2) Cloning repos locally ==="
debug "Running clone-repos.sh with args: --file $REPOS_FILE ${DEBUG_ARGS[*]}"
clone_args=( --file "$REPOS_FILE" )
clone_args+=( "${DEBUG_ARGS[@]}" )
"$CLONE_SCRIPT" "${clone_args[@]}"

echo "=== 3) Updating VS Code workspace ==="
debug "Running vscode-workspace-add.sh with args: -f $REPOS_FILE ${DEBUG_ARGS[*]}"
workspace_args=( -f "$REPOS_FILE" )
workspace_args+=( "${DEBUG_ARGS[@]}" )
"$WORKSPACE_SCRIPT" "${workspace_args[@]}"

if $CODESPACES_FLAG; then
  debug "Codespaces flag enabled, will run codespaces auth step"
  if [ -x "$CODESPACES_SCRIPT" ]; then
    echo "=== 4) Injecting Codespaces permissions ==="
    debug "Running codespaces-auth-add.sh"
    codespaces_args=( -f "$REPOS_FILE" )
    
    # Add devcontainer paths if specified
    if [ ${#DEVCONTAINER_PATHS[@]} -gt 0 ]; then
      for devpath in "${DEVCONTAINER_PATHS[@]}"; do
        codespaces_args+=( -d "$devpath" )
      done
    else
      # Default to PROJECT_ROOT/.devcontainer/devcontainer.json if it exists
      if [ -f "$PROJECT_ROOT/.devcontainer/devcontainer.json" ]; then
        codespaces_args+=( -d "$PROJECT_ROOT/.devcontainer/devcontainer.json" )
      else
        echo "Warning: No devcontainer.json paths specified and default path not found."
        debug "Default devcontainer.json not found at: $PROJECT_ROOT/.devcontainer/devcontainer.json"
      fi
    fi
    
    [ -n "$PERMISSIONS_OPT" ] && codespaces_args+=( --permissions "$PERMISSIONS_OPT" )
    [ -n "$TOOL_OPT" ]       && codespaces_args+=( -t "$TOOL_OPT" )
    codespaces_args+=( "${DEBUG_ARGS[@]}" )
    "$CODESPACES_SCRIPT" "${codespaces_args[@]}"
  else
    echo "Warning: codespaces-auth-add.sh not found; skipping Codespaces auth step."
    debug "codespaces-auth-add.sh not executable: $CODESPACES_SCRIPT"
  fi
else
  echo "Skipping Codespaces auth step (use --codespaces or -d to enable)."
  debug "Codespaces flag not set"
fi

echo "✅ Setup complete."
debug "=== Setup-repos.sh Debug Session Ended ==="

# Close debug file descriptor if opened
if [ -n "$DEBUG_FILE" ]; then
  exec 3>&-
fi
