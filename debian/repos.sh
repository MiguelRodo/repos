#!/usr/bin/env bash
# repos - Multi-repository management tool wrapper
# Dispatches subcommands to the appropriate script

set -euo pipefail

SCRIPT_DIR="/usr/share/repos/scripts"

usage() {
  cat <<EOF
Usage: repos <command> [options]

Commands:
  clone      Clone repositories listed in repos.list into the parent directory
  setup      Clone and configure repositories (includes VS Code workspace and
             optional Codespaces authentication)
  workspace  Generate (or update) the VS Code multi-root workspace file
  run        Execute a script inside each cloned repository

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
  setup)
    shift; exec "$SCRIPT_DIR/setup-repos.sh" "$@" ;;
  workspace)
    shift; exec "$SCRIPT_DIR/helper/vscode-workspace-add.sh" "$@" ;;
  run)
    shift; exec "$SCRIPT_DIR/run-pipeline.sh" "$@" ;;
  *)
    echo "Error: unknown command '$1'" >&2; echo "" >&2; usage >&2; exit 1 ;;
esac
