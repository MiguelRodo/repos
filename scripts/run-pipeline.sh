#!/usr/bin/env bash
# run-pipeline.sh — Multi-repo pipeline executor with setup integration
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# This script:
# 1. Runs setup-repos.sh to ensure repositories are cloned and configured
# 2. Installs R dependencies (if install-r-deps.sh exists)
# 3. Executes a script (default: run.sh) in each repository (if present)
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
3. Executes a script (default: run.sh) in each repository (if present)

Options:
  -f, --file <file>        Repo list file (default: repos.list)
      --script <path>      Script to run in each repo, relative to repo root
                           (default: run.sh)
  -i, --include <names>    Comma-separated list of repo names to INCLUDE
  -e, --exclude <names>    Comma-separated list of repo names to EXCLUDE
  -s, --skip-setup         Skip the setup-repos.sh step
  -d, --skip-deps          Skip the install-r-deps.sh step
  -n, --dry-run            Show what would be done, but don't execute
  -v, --verbose            Enable verbose logging
      --no-stop-on-error   Continue on failure, report all results in summary
  -h, --help               Show this message

Path Resolution (follows clone-repos.sh logic):
  All repositories are located in the parent directory of the current directory.
  - For @branch lines: ../<fallback_repo>-<branch> or ../target_dir
  - For clone lines: ../repo_name or ../target_dir
  - Run from the directory containing repos.list (usually PROJECT_ROOT)

File Format:
  The --file can be a standard repos.list (fully-specified format) or a
  concise format with one directory name per line, optionally followed by
  a script name:
    repo-directory-1
    repo-directory-2 pipeline.sh
    repo-directory-3

If a folder exists and contains the target script, this script will make it
executable and then run it.
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
  RUN_SCRIPT="run.sh"
  STOP_ON_ERROR=true

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--file)
        shift; REPOS_FILE="$1"; shift ;;
      --script)
        shift; RUN_SCRIPT="$1"; shift ;;
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
      --no-stop-on-error)
        STOP_ON_ERROR=false; shift ;;
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

# --- Detect concise format ---
# A concise list file contains only directory names (and optional script names),
# no org/repo, @branch, or global flags like --codespaces / --worktree / --public / --private.
is_concise_format() {
  local file="$1"
  while IFS= read -r line || [ -n "$line" ]; do
    # Strip leading/trailing whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    # Skip empty lines and comments
    [ -z "$line" ] && continue
    [[ "$line" == \#* ]] && continue
    # If line contains '/' or starts with '@' or is a global flag, it's fully-specified
    case "$line" in
      */*|@*|--codespaces*|--worktree*|--public*|--private*)
        return 1 ;;
    esac
  done < "$file"
  return 0
}

# --- Summary helpers ---
SUMMARY_LINES=()
TOTAL_COUNT=0
SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

record_success() {
  local repo="$1" script_name="$2"
  SUMMARY_LINES+=("✅ ${repo}/${script_name} — success")
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
}

record_fail() {
  local repo="$1" script_name="$2" code="$3"
  SUMMARY_LINES+=("❌ ${repo}/${script_name} — failed (exit code ${code})")
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

record_skip() {
  local repo="$1" script_name="$2"
  SUMMARY_LINES+=("⏭  ${repo} — no ${script_name} found")
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
  SKIP_COUNT=$((SKIP_COUNT + 1))
}

print_summary() {
  echo ""
  echo "=== Pipeline Summary ==="
  for line in "${SUMMARY_LINES[@]}"; do
    echo "$line"
  done
  echo ""
  echo "Total: ${TOTAL_COUNT} repositories | ${SUCCESS_COUNT} succeeded | ${FAIL_COUNT} failed | ${SKIP_COUNT} skipped"
}

# --- Execute script in a single repo directory ---
run_in_repo() {
  local full_path="$1" repo_name="$2" script_name="$3"

  if ! should_process "$repo_name"; then
    $VERBOSE && echo "Skipping $repo_name"
    return 0
  fi

  if [ -d "$full_path" ]; then
    local target="$full_path/$script_name"
    if [ -f "$target" ]; then
      echo "⏵ $repo_name: $script_name found"
      if $DRY_RUN; then
        echo "  DRY-RUN: would chmod +x and execute $target"
        record_success "$repo_name" "$script_name"
      else
        $VERBOSE && echo "  chmod +x \"$target\""
        chmod +x "$target"
        $VERBOSE && echo "  cd \"$full_path\" && ./$script_name"
        local rc=0
        ( cd "$full_path" && "./$script_name" ) || rc=$?
        if [ $rc -eq 0 ]; then
          record_success "$repo_name" "$script_name"
        else
          record_fail "$repo_name" "$script_name" "$rc"
          if [ "$STOP_ON_ERROR" = true ]; then
            print_summary
            exit $rc
          fi
        fi
      fi
    else
      $VERBOSE && echo "⏭ $repo_name: no $script_name"
      record_skip "$repo_name" "$script_name"
    fi
  else
    $VERBOSE && echo "⚠️  Folder not found: $full_path"
    record_skip "$repo_name" "$script_name"
  fi
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

  # Step 3: Run each repository's script
  echo "=== 3) Executing $RUN_SCRIPT in repositories ==="

  # Check if the list file uses concise format
  if is_concise_format "$REPOS_FILE"; then
    $VERBOSE && echo "Detected concise format in $REPOS_FILE"
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$line" ] && continue
      [[ "$line" == \#* ]] && continue

      # Parse: <dir_name> [script_name]
      local dir_name script_name
      dir_name="$(echo "$line" | awk '{print $1}')"
      script_name="$(echo "$line" | awk '{print $2}')"
      [ -z "$script_name" ] && script_name="$RUN_SCRIPT"

      local full_path
      full_path="$(cd "$PROJECT_ROOT/.." && pwd)/$dir_name"
      run_in_repo "$full_path" "$dir_name" "$script_name"
    done < "$REPOS_FILE"

    print_summary
    [ $FAIL_COUNT -gt 0 ] && exit 1
    return 0
  fi

  # Fully-specified format: use workspace file (more reliable after setup)
  local workspace_file=""
  if [ -f "$PROJECT_ROOT/entire-project.code-workspace" ]; then
    workspace_file="$PROJECT_ROOT/entire-project.code-workspace"
  elif [ -f "$PROJECT_ROOT/EntireProject.code-workspace" ]; then
    workspace_file="$PROJECT_ROOT/EntireProject.code-workspace"
  fi
  
  if [ -n "$workspace_file" ] && command -v jq >/dev/null 2>&1; then
    while IFS= read -r folder_path; do
      local full_path="$PROJECT_ROOT/$folder_path"
      local repo_name
      repo_name="$(basename "$full_path")"
      run_in_repo "$full_path" "$repo_name" "$RUN_SCRIPT"
    done < <(jq -r '.folders[].path' "$workspace_file")

    print_summary
    [ $FAIL_COUNT -gt 0 ] && exit 1
  else
    echo "Warning: No workspace file or jq not available. Cannot execute scripts."
    echo "Run 'repos setup' first to generate the workspace file."
    exit 1
  fi
}

main "$@"
