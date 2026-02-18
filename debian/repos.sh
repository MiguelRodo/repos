#!/usr/bin/env bash
# repos - Multi-repository management tool wrapper
# Dispatches subcommands to the appropriate script

set -euo pipefail

SCRIPT_DIR="/usr/share/repos/scripts"

usage() {
  cat <<EOF
Usage: repos <command> [options]

Commands:
  setup    Clone and configure repositories from a repos.list file
  run      Execute a script inside each cloned repository

Run 'repos <command> --help' for more information on a command.
EOF
}

if [ $# -eq 0 ]; then
  usage >&2; exit 1
fi

case "$1" in
  -h|--help)
    usage; exit 0 ;;
  setup)
    shift; exec "$SCRIPT_DIR/setup-repos.sh" "$@" ;;
  run)
    shift; exec "$SCRIPT_DIR/run-pipeline.sh" "$@" ;;
  *)
    echo "Error: unknown command '$1'" >&2; echo "" >&2; usage >&2; exit 1 ;;
esac
