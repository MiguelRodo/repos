#!/usr/bin/env bash
# run-pipeline.sh — Multi-repo pipeline executor with setup integration
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# This script:
# 1. Runs setup-repos.sh to ensure repositories are cloned and configured
# 2. Installs R dependencies (if install-r-deps.sh exists)
# 3. Executes run.sh in each repository (if present)
#
# Path logic follows clone-repos.sh conventions

set -Eeo pipefail

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SETUP_SCRIPT="$SCRIPT_DIR/setup-repos.sh"
INSTALL_DEPS_SCRIPT="$SCRIPT_DIR/helper/install-r-deps.sh"

# --- Prerequisites ---
check_prerequisites() {
  for cmd in git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: '$cmd' is required but not found in PATH." >&2
      exit 1
    fi
  done
}

# --- Usage ---
usage() {
  cat <<EOF
Usage: $0 [options]

This script runs the analysis pipeline across all repositories:
1. Runs setup-repos.sh to ensure repositories are cloned and configured
2. Installs R dependencies (if install-r-deps.sh exists)  
3. Executes run.sh in each repository (if present)

Options:
  -f, --file <file>        Repo list file (default: repos.list)
  -i, --include <names>    Comma-separated list of repo names to INCLUDE
  -e, --exclude <names>    Comma-separated list of repo names to EXCLUDE
  -s, --skip-setup         Skip the setup-repos.sh step
  -d, --skip-deps          Skip the install-r-deps.sh step
  -n, --dry-run            Show what would be done, but don't execute
  -v, --verbose            Enable verbose logging
  -h, --help               Show this message

Path Resolution (follows clone-repos.sh logic):
  All repositories are located in the parent directory of the current directory.
  - For @branch lines: ../<fallback_repo>-<branch> or ../target_dir
  - For clone lines: ../repo_name or ../target_dir
  - Run from the directory containing repos.list (usually PROJECT_ROOT)

If a folder exists and contains run.sh, this script will make it executable
and then run it. One failing run.sh stops the process.
EOF
}

# --- Parse arguments ---
parse_args() {
  if [ ! -f "$PROJECT_ROOT/repos.list" ] && [ -f "$PROJECT_ROOT/repos-to-clone.list" ]; then
    REPOS_FILE="$PROJECT_ROOT/repos-to-clone.list"
  else
    REPOS_FILE="$PROJECT_ROOT/repos.list"
  fi
  
  SKIP_SETUP=false
  SKIP_DEPS=false
  DRY_RUN=false
  VERBOSE=false
  INCLUDE_RAW=""
  EXCLUDE_RAW=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--file)
        shift; REPOS_FILE="$1"; shift ;;
      -i|--include)
        shift; INCLUDE_RAW="$1"; shift ;;
      -e|--exclude)
        shift; EXCLUDE_RAW="$1"; shift ;;
      -s|--skip-setup)
        SKIP_SETUP=true; shift ;;
      -d|--skip-deps)
        SKIP_DEPS=true; shift ;;
      -n|--dry-run)
        DRY_RUN=true; shift ;;
      -v|--verbose)
        VERBOSE=true; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        echo "Unknown option: $1" >&2
        usage; exit 1 ;;
    esac
  done

  if [ ! -f "$REPOS_FILE" ]; then
    echo "Error: repo list '$REPOS_FILE' not found." >&2
    exit 1
  fi

  IFS=',' read -r -a INCLUDE <<< "$INCLUDE_RAW"
  IFS=',' read -r -a EXCLUDE <<< "$EXCLUDE_RAW"
}

# --- Filter logic ---
should_process() {
  local name="$1"
  if [ "${#INCLUDE[@]}" -gt 0 ]; then
    local found=0
    for inc in "${INCLUDE[@]}"; do
      [ "$inc" = "$name" ] && found=1
    done
    [ $found -eq 1 ] || return 1
  fi
  if [ "${#EXCLUDE[@]}" -gt 0 ]; then
    for exc in "${EXCLUDE[@]}"; do
      [ "$exc" = "$name" ] && return 1
    done
  fi
  return 0
}

# --- Main ---
main() {
  check_prerequisites
  parse_args "$@"
  
  # Change to PROJECT_ROOT to match clone-repos.sh behavior
  cd "$PROJECT_ROOT"

  # Step 1: Run setup (unless skipped)
  if [ "$SKIP_SETUP" = false ]; then
    if [ -x "$SETUP_SCRIPT" ]; then
      echo "=== 1) Running setup-repos.sh ==="
      if $DRY_RUN; then
        echo "  DRY-RUN: would execute $SETUP_SCRIPT -f $REPOS_FILE"
      else
        "$SETUP_SCRIPT" -f "$REPOS_FILE"
      fi
    else
      echo "Warning: setup-repos.sh not found or not executable; skipping setup step."
    fi
  else
    echo "=== 1) Skipping setup step (--skip-setup) ==="
  fi

  # Step 2: Install R dependencies (unless skipped)
  if [ "$SKIP_DEPS" = false ]; then
    if [ -x "$INSTALL_DEPS_SCRIPT" ]; then
      echo "=== 2) Installing R dependencies ==="
      if $DRY_RUN; then
        echo "  DRY-RUN: would execute $INSTALL_DEPS_SCRIPT"
      else
        "$INSTALL_DEPS_SCRIPT" || echo "Warning: install-r-deps.sh failed; continuing..."
      fi
    else
      $VERBOSE && echo "Note: install-r-deps.sh not found; skipping dependency installation."
    fi
  else
    echo "=== 2) Skipping R dependencies (--skip-deps) ==="
  fi

  # Step 3: Run each repository's run.sh
  echo "=== 3) Executing run.sh in repositories ==="
  
  # Use the install-r-deps.sh approach: parse workspace file
  local workspace_file=""
  if [ -f "$PROJECT_ROOT/entire-project.code-workspace" ]; then
    workspace_file="$PROJECT_ROOT/entire-project.code-workspace"
  elif [ -f "$PROJECT_ROOT/EntireProject.code-workspace" ]; then
    workspace_file="$PROJECT_ROOT/EntireProject.code-workspace"
  fi
  
  if [ -n "$workspace_file" ] && command -v jq >/dev/null 2>&1; then
    # Use workspace file (more reliable after setup)
    local found_any=false
    while IFS= read -r folder_path; do
      local full_path="$PROJECT_ROOT/$folder_path"
      local repo_name="$(basename "$full_path")"
      
      if ! should_process "$repo_name"; then
        $VERBOSE && echo "Skipping $repo_name"
        continue
      fi
      
      if [ -d "$full_path" ]; then
        local script="$full_path/run.sh"
        if [ -f "$script" ]; then
          echo "⏵ $repo_name: run.sh found"
          found_any=true
          if $DRY_RUN; then
            echo "  DRY-RUN: would chmod +x and execute $script"
          else
            $VERBOSE && echo "  chmod +x \"$script\""
            chmod +x "$script"
            $VERBOSE && echo "  cd \"$full_path\" && ./run.sh"
            ( cd "$full_path" && ./run.sh )
          fi
        else
          $VERBOSE && echo "⏭ $repo_name: no run.sh"
        fi
      else
        $VERBOSE && echo "⚠️  Folder not found: $full_path"
      fi
    done < <(jq -r '.folders[].path' "$workspace_file")
    
    if [ "$found_any" = false ]; then
      echo "ℹ️  No run.sh found in any of the repositories."
    else
      echo "✅ Pipeline execution complete."
    fi
  else
    echo "Warning: No workspace file or jq not available. Cannot execute run.sh scripts."
    echo "Run 'scripts/setup-repos.sh' first to generate the workspace file."
    exit 1
  fi
}

main "$@"
