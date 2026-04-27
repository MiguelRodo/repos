#!/usr/bin/env bash
# repos - Multi-repository management tool wrapper
# Dispatches subcommands to the appropriate script

set -euo pipefail

SCRIPT_DIR="/usr/share/repos/scripts"

usage() {
  cat <<EOF
Usage: repos <command> [options]

Commands:
  clone       Clone repositories listed in repos.list into the parent directory
  workspace   Generate (or update) the VS Code multi-root workspace file
  codespace   Configure GitHub Codespaces authentication
  codespaces  Alias for codespace
  run         Execute a script inside each cloned repository

Run 'repos <command> --help' for more information on a command.
EOF
}

if [ $# -eq 0 ]; then
  usage >&2; exit 1
fi

case "$1" in
  -h|--help)
    usage; exit 0 ;;
  clone)
    shift; exec "$SCRIPT_DIR/helper/clone-repos.sh" "$@" ;;
  workspace)
    shift; exec "$SCRIPT_DIR/helper/vscode-workspace-add.sh" "$@" ;;
  codespace|codespaces)
    shift; exec "$SCRIPT_DIR/helper/codespaces-auth-add.sh" "$@" ;;
  run)
    shift; exec "$SCRIPT_DIR/run-pipeline.sh" "$@" ;;
  *)
    echo "Error: unknown command '$1'" >&2; echo "" >&2; usage >&2; exit 1 ;;
esac
