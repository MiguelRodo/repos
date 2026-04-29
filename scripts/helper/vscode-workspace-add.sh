#!/usr/bin/env bash
# vscode-workspace-add.sh — VS Code workspace updater for multi-repo / multi-branch setups
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
# Requires: bash 3.2+, mktemp
#
# Behaviour:
#   • Lines starting with "@<branch>" inherit a "fallback repo":
#       - Initially: the CURRENT repo's remote (the repo that contains repos.list).
#       - After each clone line: fallback updates to the repo used/implied by that line.
#   • "@<branch>" resolves to a clone path by default.
#   • Per-line opt-in: add "--worktree" or "-w" to treat @branch as a worktree instead.
#
# Examples (repos.list):
#   @data-tidy data-tidy                 # uses current repo as fallback (clone path)
#   SATVILab/projr                       # fallback → SATVILab/projr
#   @dev                                 # clone path on SATVILab/projr
#   @dev-miguel --worktree               # worktree path on SATVILab/projr
#   SATVILab/Analysis@test               # fallback → SATVILab/Analysis
#   @tweak                               # clone path on SATVILab/Analysis
#   @dev-2 --worktree                    # worktree path on SATVILab/Analysis

set -euo pipefail

# Global array for temporary files to clean up on exit
declare -a CLEANUP_FILES=()
# Use Bash 3.2-safe array expansion to avoid "unbound variable" error with set -u
# shellcheck disable=SC2154  # f is the for-loop variable inside the trap string
trap 'for f in ${CLEANUP_FILES[@]+"${CLEANUP_FILES[@]}"}; do rm -f -- "$f"; done' EXIT

# — Debug support —
DEBUG=false
DEBUG_FILE=""
DEBUG_FD=3  # Use FD 3 for debug output (compatible with Bash 3.2+)

debug() {
  if $DEBUG; then
    printf "[DEBUG vscode-workspace-add.sh] %s\n" "$*" >&$DEBUG_FD
  fi
}

# Get platform-independent temp directory
get_temp_dir() {
  # Try various temp directory variables in order of preference
  if [ -n "${TMPDIR:-}" ] && [ -d "${TMPDIR}" ]; then
    printf '%s\n' "${TMPDIR%/}"  # Remove trailing slash if present
  elif [ -n "${TEMP:-}" ] && [ -d "${TEMP}" ]; then
    printf '%s\n' "${TEMP%/}"
  elif [ -n "${TMP:-}" ] && [ -d "${TMP}" ]; then
    printf '%s\n' "${TMP%/}"
  elif [ -d "/tmp" ]; then
    printf '%s\n' "/tmp"
  else
    # Fallback to current directory
    printf '%s\n' "."
  fi
}

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -f, --file <file>       Specify the repository list file (default: 'repos.list').
  -d, --debug             Enable debug output to stderr (shows path calculations).
  --debug-file [file]     Enable debug output to file (auto-generated if not specified).
  -h, --help              Display this help message.

Each line in the repository list file can be in one of three formats:

1) Clone a repo (default branch, or all branches with -a)
   owner/repo [target_directory] [-a|--all-branches]
   https://host/owner/repo [target_directory] [-a|--all-branches]

2) Clone exactly one branch
   owner/repo@branch [target_directory]

3) Clone a branch from the current fallback repo
   @branch [target_directory] [--worktree|-w]

Where repo_spec is one of:
  owner/repo[@branch]
  https://<host>/owner/repo[@branch]
  @branch (inherits from fallback repo)

Fallback repo rules:
  • Initially, the fallback repo is the repository containing repos.list.
  • After any successful clone line (1 or 2), the fallback repo becomes that
    newly cloned directory. @branch lines then resolve to worktree paths off it.
  • @branch lines themselves do not change the fallback.

Examples:
  user1/project1
  user2/project2@develop ./Projects/Repo2
  https://gitlab.com/user4/project4@feature-branch ./GitLabRepos
  @analysis analysis                   # clone off current repo
  SATVILab/stimgate                    # fallback updates
  @dev  stimgate-dev --worktree        # worktree off SATVILab/stimgate
EOF
}

# --- Update workspace with jq ---
update_with_jq() {
  local workspace_file="$1"
  local paths_list="$2"
  local folders_json_file=""
  local tmp_file=""
  local paths_list_file=""

  folders_json_file="$(mktemp "$(get_temp_dir)/repos-folders-XXXXXX")"
  CLEANUP_FILES+=("$folders_json_file")
  paths_list_file="$(mktemp "$(get_temp_dir)/repos-paths-list-XXXXXX")"
  CLEANUP_FILES+=("$paths_list_file")

  printf '%s\n' "$paths_list" > "$paths_list_file"

  # build an array of {path: "..."} objects and save to file
  jq -R . -- "$paths_list_file" \
    | jq -s '[ .[] | { path: . } ]' > "$folders_json_file"

  if [ ! -f "$workspace_file" ]; then
    # create a brand-new workspace file
    jq -n --slurpfile folders "$folders_json_file" \
      '{ folders: $folders[0] }' \
      > "$workspace_file"
  else
    # merge into existing file: set .folders = $folders
    tmp_file="$(mktemp "$(get_temp_dir)/repos-workspace-XXXXXX")"
    CLEANUP_FILES+=("$tmp_file")
    jq --slurpfile folders "$folders_json_file" \
       '.folders = $folders[0]' \
       -- "$workspace_file" > "$tmp_file" \
      && mv -- "$tmp_file" "$workspace_file"
  fi
  rm -f -- "$folders_json_file" "$tmp_file"

  printf "Updated '%s' with jq.\n" "$workspace_file"
}

# --- Update workspace with Python ---
PYTHON_UPDATE_SCRIPT=$(cat <<'PYCODE'
import sys, json, os
ws = sys.argv[1]
paths_file = sys.argv[2]
with open(paths_file, 'r') as f:
    paths = [line.strip() for line in f if line.strip()]
try:
    with open(ws) as f:
        data = json.load(f)
except Exception:
    data = {}
data['folders'] = [{'path': p} for p in paths]
with open(ws, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PYCODE
)

update_with_python() {
  local workspace_file="$1"
  local paths_list="$2"
  local paths_file=""
  paths_file="$(mktemp "$(get_temp_dir)/repos-paths-XXXXXX")"
  CLEANUP_FILES+=("$paths_file")
  printf '%s\n' "$paths_list" > "$paths_file"
  # Use - and passing filename as argument, without redundant -- which can break indexing
  python - "$workspace_file" "$paths_file" <<<"$PYTHON_UPDATE_SCRIPT"
  rm -f -- "$paths_file"
  printf "Updated '%s' with Python.\n" "$workspace_file"
}

update_with_python3() {
  local workspace_file="$1"
  local paths_list="$2"
  local paths_file=""
  paths_file="$(mktemp "$(get_temp_dir)/repos-paths-XXXXXX")"
  CLEANUP_FILES+=("$paths_file")
  printf '%s\n' "$paths_list" > "$paths_file"
  python3 - "$workspace_file" "$paths_file" <<<"$PYTHON_UPDATE_SCRIPT"
  rm -f -- "$paths_file"
  printf "Updated '%s' with Python3.\n" "$workspace_file"
}

update_with_py() {
  local workspace_file="$1"
  local paths_list="$2"
  local paths_file=""
  paths_file="$(mktemp "$(get_temp_dir)/repos-paths-XXXXXX")"
  CLEANUP_FILES+=("$paths_file")
  printf '%s\n' "$paths_list" > "$paths_file"
  py - "$workspace_file" "$paths_file" <<<"$PYTHON_UPDATE_SCRIPT"
  rm -f -- "$paths_file"
  printf "Updated '%s' with py launcher.\n" "$workspace_file"
}


# --- Update workspace with Rscript (jsonlite) ---
update_with_rscript() {
  local workspace_file="$1"
  local paths_list="$2"
  local paths_file=""
  paths_file="$(mktemp "$(get_temp_dir)/repos-paths-XXXXXX")"
  CLEANUP_FILES+=("$paths_file")
  printf '%s\n' "$paths_list" > "$paths_file"
  Rscript --vanilla - "$workspace_file" "$paths_file" <<'RSCRIPT'
args <- commandArgs(trailingOnly=TRUE)
ws <- args[1]
paths_file <- args[2]

# Read and clean paths list
paths <- readLines(paths_file, warn = FALSE)
paths <- paths[nzchar(paths)]
folders <- lapply(paths, function(p) list(path = p))

# Determine a writable user library
user_lib <- Sys.getenv("R_LIBS_USER", unset = "")
if (!nzchar(user_lib)) {
  user_lib <- file.path("~", "R", "library")
}
user_lib <- path.expand(user_lib)
if (!dir.exists(user_lib)) dir.create(user_lib, recursive = TRUE, showWarnings = FALSE)

# Install jsonlite if missing, into the user library
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  install.packages(
    "jsonlite",
    repos = "https://cloud.r-project.org",
    lib   = user_lib
  )
}

# Load or initialize existing workspace JSON
if (file.exists(ws)) {
  data <- tryCatch(jsonlite::fromJSON(ws), error = function(e) list())
} else {
  data <- list()
}

# Overwrite / set the folders element
data$folders <- folders

# Write out prettified JSON
jsonlite::write_json(
  data,
  path        = ws,
  pretty      = TRUE,
  auto_unbox  = TRUE
)
RSCRIPT
  rm -f -- "$paths_file"

  printf "Updated '%s' with Rscript.\n" "$workspace_file"
}




get_workspace_file() {
  # Prefer lower-case, but use CamelCase if that's all there is
  local current_dir="$1"
  local workspace_file="$current_dir/entire-project.code-workspace"
  local workspace_file_camel="$current_dir/EntireProject.code-workspace"
  if [ -f "$workspace_file" ]; then
    printf '%s\n' "$workspace_file"
  elif [ -f "$workspace_file_camel" ]; then
    printf '%s\n' "$workspace_file_camel"
  else
    # If neither exists, will create lower-case one by default
    printf '%s\n' "$workspace_file"
  fi
}

spec_to_repo_name() {
  # Extract repo name from owner/repo or https URL
  local spec="$1"
  case "$spec" in
    https://*)
      spec="${spec%.git}"
      basename -- "$spec"
      ;;
    */*)
      spec="${spec%.git}"
      printf '%s\n' "${spec##*/}"
      ;;
    *)
      printf '%s\n' "$spec"
      ;;
  esac
}

# Sanitize branch name for use in directory paths
# Replaces forward slashes with dashes to avoid nested directories
sanitize_branch_name() {
  local branch="$1"
  printf '%s\n' "${branch//\//-}"
}

# Validate target_dir to prevent path traversal and argument injection
validate_target_dir() {
  local dir="$1"
  if [ -n "$dir" ]; then
    case "$dir" in
      /*|*..*|-*)
        printf "Error: target directory cannot be absolute, contain '..', or start with a hyphen: %s\n" "$dir" >&2
        return 1
        ;;
    esac
  fi
  return 0
}

build_paths_list() {
  local repos_list_file="$1"
  local current_dir="$2"
  local debug="${3:-false}"
  local parent_dir
  parent_dir="$(dirname -- "$current_dir")"
  
  local paths_list="."
  local line trimmed first target_dir branch repo_spec repo_no_ref ref
  local fallback_repo_name repo_name is_worktree repo_path relative_repo_path
  
  # --- Planning phase: count references per repo ---
  declare -a plan_repo_names=()
  declare -a plan_ref_counts=()
  
  local plan_repo_idx plan_repo_name plan_fallback_name use_worktree target_dir repo_path
  
  # Initialize fallback to current repo
  plan_fallback_name="$(basename -- "$current_dir")"
  
  [[ "$debug" == true ]] && printf "[DEBUG] Planning phase: counting references\n" >&2
  [[ "$debug" == true ]] && printf "[DEBUG] Planning fallback starts as: %s\n" "$plan_fallback_name" >&2
  
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in \#*|"") continue ;; esac
    case "$trimmed" in *" # "*) trimmed="${trimmed%% # *}" ;; *" #"*) trimmed="${trimmed%% #*}" ;; esac
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"; trimmed=${trimmed%$'\r'}
    [ -z "$trimmed" ] && continue
    
    # Skip global flag lines (not relevant to workspace generation)
    case "$trimmed" in
      --codespaces|--codespaces[[:space:]]*|\
      --public|--public[[:space:]]*|\
      --private|--private[[:space:]]*|\
      --worktree|--worktree[[:space:]]*)
        continue
        ;;
    esac

    set -f
    set -- $trimmed
    [ "$#" -eq 0 ] && { set +f; continue; }
    
    first="$1"; shift
    case "$first" in
      @*)
        # @branch line: count as reference to fallback repo only if using --worktree
        use_worktree=0
        target_dir=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -w|--worktree) use_worktree=1 ;;
            -a|--all-branches|--public|--private|--codespaces) ;; # ignore
            -*)
              printf "Error: unknown option '%s' on line: %s\n" "$1" "$trimmed" >&2
              set +f; return 1 ;;
            *)
              if [ -z "$target_dir" ]; then
                target_dir="$1"
              fi
              ;;
          esac
          shift
        done
        
        validate_target_dir "$target_dir" || { set +f; return 1; }

        if [ "$use_worktree" -eq 1 ]; then
          # This is a worktree, count it as a reference to fallback
          plan_repo_name="$plan_fallback_name"
          
          # Find or add this repo in the plan
          plan_repo_idx=-1
          for i in "${!plan_repo_names[@]}"; do
            if [ "${plan_repo_names[$i]}" = "$plan_repo_name" ]; then
              plan_repo_idx=$i
              break
            fi
          done
          
          if [ "$plan_repo_idx" -ge 0 ]; then
            plan_ref_counts[$plan_repo_idx]=$((${plan_ref_counts[$plan_repo_idx]} + 1))
          else
            plan_repo_names+=("$plan_repo_name")
            plan_ref_counts+=("1")
          fi
          [[ "$debug" == true ]] && printf "[DEBUG]   Plan: worktree on fallback=%s, count=%d\n" "$plan_fallback_name" "${plan_ref_counts[${#plan_ref_counts[@]}-1]}" >&2
        fi
        # Note: worktree lines don't change the fallback
        ;;
      *)
        # Clone line: extract repo name
        repo_spec="$first"
        target_dir=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -a|--all-branches|--public|--private|--codespaces) ;; # ignore
            -*)
              printf "Error: unknown option '%s' on line: %s\n" "$1" "$trimmed" >&2
              set +f; return 1 ;;
            *)
              if [ -z "$target_dir" ]; then
                target_dir="$1"
              fi
              ;;
          esac
          shift
        done

        validate_target_dir "$target_dir" || { set +f; return 1; }

        case "$repo_spec" in
          *@*) repo_no_ref="${repo_spec%@*}" ;;
          *)   repo_no_ref="$repo_spec" ;;
        esac

        # Validate repo_no_ref to prevent path traversal and argument injection
        case "$repo_no_ref" in
          -*|*..*)
            printf "Error: repository spec cannot start with a hyphen or contain '..': %s\n" "$repo_no_ref" >&2
            set +f; return 1
            ;;
        esac

        plan_repo_name="$(spec_to_repo_name "$repo_no_ref")"
        
        # Find or add this repo in the plan
        plan_repo_idx=-1
        for i in "${!plan_repo_names[@]}"; do
          if [ "${plan_repo_names[$i]}" = "$plan_repo_name" ]; then
            plan_repo_idx=$i
            break
          fi
        done
        
        if [ "$plan_repo_idx" -ge 0 ]; then
          plan_ref_counts[$plan_repo_idx]=$((${plan_ref_counts[$plan_repo_idx]} + 1))
        else
          plan_repo_names+=("$plan_repo_name")
          plan_ref_counts+=("1")
        fi
        [[ "$debug" == true ]] && printf "[DEBUG]   Plan: clone repo=%s, count=%d\n" "$plan_repo_name" "${plan_ref_counts[${#plan_ref_counts[@]}-1]}" >&2
        
        # Update fallback for subsequent lines
        plan_fallback_name="$plan_repo_name"
        [[ "$debug" == true ]] && printf "[DEBUG]   Plan: fallback updated to %s\n" "$plan_fallback_name" >&2
        ;;
    esac
    set +f
  done < "$repos_list_file"
  
  [[ "$debug" == true ]] && printf "[DEBUG] Planning complete\n" >&2
  
  # --- Main processing: build paths ---
  # Initialize fallback to current repo (the one containing repos.list)
  fallback_repo_name="$(basename -- "$current_dir")"
  [[ "$debug" == true ]] && printf "[DEBUG] Initial fallback repo: %s\n" "$fallback_repo_name" >&2

  while IFS= read -r line || [ -n "$line" ]; do
    # Trim and skip comments/blank lines
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in \#*|"") continue ;; esac
    case "$trimmed" in *" # "*) trimmed="${trimmed%% # *}" ;; *" #"*) trimmed="${trimmed%% #*}" ;; esac
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"; trimmed=${trimmed%$'\r'}
    [ -z "$trimmed" ] && continue
    
    [[ "$debug" == true ]] && printf "[DEBUG] Processing line: %s\n" "$trimmed" >&2

    # Skip global flag lines (not relevant to workspace generation)
    case "$trimmed" in
      --codespaces|--codespaces[[:space:]]*|\
      --public|--public[[:space:]]*|\
      --private|--private[[:space:]]*|\
      --worktree|--worktree[[:space:]]*)
        continue
        ;;
    esac

    # Parse the line (word splitting is intentional)
    set -f
    # shellcheck disable=SC2086
    set -- $trimmed
    [ "$#" -eq 0 ] && { set +f; continue; }
    
    first="$1"; shift
    target_dir=""
    is_worktree=0
    use_worktree=0
    
    case "$first" in
      @*)
        # @branch line: @branch [target_dir] [--worktree|-w]
        branch="${first#@}"
        if [ -z "$branch" ] || [[ "$branch" == -* ]] || ! git check-ref-format --allow-onelevel "$branch"; then
          printf "Error: '%s' is not a valid Git branch name.\n" "$branch" >&2
          set +f; return 1
        fi
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -w|--worktree) use_worktree=1 ;;
            -a|--all-branches|--public|--private|--codespaces) ;; # ignore for path calculation
            -*)
              printf "Error: unknown option '%s' on line: %s\n" "$1" "$trimmed" >&2
              set +f; return 1 ;;
            *)
              if [ -z "$target_dir" ]; then
                target_dir="$1"
              fi
              ;;
          esac
          shift
        done
        
        validate_target_dir "$target_dir" || { set +f; return 1; }

        # Determine if this is a worktree or clone
        is_worktree=$use_worktree
        
        if [ "$is_worktree" -eq 1 ]; then
          # Worktree path: ../<fallback_repo>-<branch> or ../<target_dir>
          if [ -n "$target_dir" ]; then
            repo_path="$parent_dir/$target_dir"
          else
            local safe_branch; safe_branch="$(sanitize_branch_name "$branch")"
            repo_path="$parent_dir/${fallback_repo_name}-${safe_branch}"
          fi
          [[ "$debug" == true ]] && printf "[DEBUG]   @branch (worktree): branch=%s, fallback=%s, path=%s\n" "$branch" "$fallback_repo_name" "$repo_path" >&2
        else
          # Clone path: same as owner/repo@branch
          if [ -n "$target_dir" ]; then
            repo_path="$parent_dir/$target_dir"
          else
            local safe_branch; safe_branch="$(sanitize_branch_name "$branch")"
            repo_path="$parent_dir/${fallback_repo_name}-${safe_branch}"
          fi
          [[ "$debug" == true ]] && printf "[DEBUG]   @branch (clone): branch=%s, fallback=%s, path=%s\n" "$branch" "$fallback_repo_name" "$repo_path" >&2
        fi
        ;;
      *)
        # Clone line: owner/repo[@branch] [target_dir]
        repo_spec="$first"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -a|--all-branches|--public|--private|--codespaces) ;; # ignore for path calculation
            -w|--worktree) ;; # ignore on clone lines
            -*)
              printf "Error: unknown option '%s' on line: %s\n" "$1" "$trimmed" >&2
              set +f; return 1 ;;
            *)
              if [ -z "$target_dir" ]; then
                target_dir="$1"
              fi
              ;;
          esac
          shift
        done
        
        validate_target_dir "$target_dir" || { set +f; return 1; }

        # Split repo_spec into repo and optional branch
        case "$repo_spec" in
          *@*) repo_no_ref="${repo_spec%@*}"; ref="${repo_spec##*@}" ;;
          *)   repo_no_ref="$repo_spec"; ref="" ;;
        esac

        if [ -n "$ref" ] && ( [[ "$ref" == -* ]] || ! git check-ref-format --allow-onelevel "$ref" ); then
          printf "Error: '%s' is not a valid Git branch name.\n" "$ref" >&2
          set +f; return 1
        fi

        # Validate repo_no_ref to prevent path traversal and argument injection
        case "$repo_no_ref" in
          -*|*..*)
            printf "Error: repository spec cannot start with a hyphen or contain '..': %s\n" "$repo_no_ref" >&2
            set +f; return 1
            ;;
        esac

        # Get the repo name for path calculation
        repo_name="$(spec_to_repo_name "$repo_no_ref")"
        
        # Look up reference count for this repo
        local repo_ref_count=1
        for i in "${!plan_repo_names[@]}"; do
          if [ "${plan_repo_names[$i]}" = "$repo_name" ]; then
            repo_ref_count="${plan_ref_counts[$i]}"
            break
          fi
        done
        
        # Calculate the path
        if [ -n "$target_dir" ]; then
          repo_path="$parent_dir/$target_dir"
        elif [ -n "$ref" ]; then
          # Single-branch clone: only append branch if multiple references exist
          if [ "$repo_ref_count" -gt 1 ]; then
            local safe_ref; safe_ref="$(sanitize_branch_name "$ref")"
            repo_path="$parent_dir/${repo_name}-${safe_ref}"
          else
            repo_path="$parent_dir/$repo_name"
          fi
        else
          # Full clone: <repo>
          repo_path="$parent_dir/$repo_name"
        fi
        
        # Update fallback for subsequent @branch lines
        fallback_repo_name="$repo_name"
        [[ "$debug" == true ]] && printf "[DEBUG]   Clone line: repo=%s, path=%s, new fallback=%s\n" "$repo_name" "$repo_path" "$fallback_repo_name" >&2
        ;;
    esac
    set +f

    # Calculate relative path from current_dir to repo_path
    if command -v realpath >/dev/null 2>&1 && realpath --help 2>&1 | grep -q -- --relative-to; then
      relative_repo_path="$(realpath --relative-to="$current_dir" -- "$repo_path" 2>/dev/null || printf '%s\n' "$repo_path")"
    else
      # Manual relative path calculation (for systems without realpath)
      # Since repo_path is in parent_dir and current_dir is inside parent_dir,
      # the relative path is always ../basename
      relative_repo_path="../$(basename -- "$repo_path")"
    fi

    [ "$relative_repo_path" = "." ] && continue
    paths_list="${paths_list}"$'\n'"$relative_repo_path"
  done < "$repos_list_file"

  printf '%s\n' "$paths_list"
}

update_workspace_file() {
  local workspace_file="$1"
  local paths_list="$2"
  [ -n "$workspace_file" ] || { printf "update_workspace_file: missing workspace_file\n" >&2; exit 1; }
  [ -n "$paths_list" ]   || { printf "update_workspace_file: missing paths_list\n"   >&2; exit 1; }


  if command -v jq >/dev/null 2>&1; then
    update_with_jq "$workspace_file" "$paths_list"
  elif command -v python >/dev/null 2>&1; then
    update_with_python "$workspace_file" "$paths_list"
  elif command -v python3 >/dev/null 2>&1; then
    update_with_python3 "$workspace_file" "$paths_list"
  elif command -v py >/dev/null 2>&1; then
    update_with_py "$workspace_file" "$paths_list"
  elif command -v Rscript >/dev/null 2>&1; then
    update_with_rscript "$workspace_file" "$paths_list"
  else
    printf "Error: none of jq, python, python3, py, or Rscript found. Cannot update workspace.\n" >&2
    exit 1
  fi
}

main() {
  local repos_list_file DEBUG DEBUG_FILE TEMP_DIR
  if [ ! -f "repos.list" ] && [ -f "repos-to-clone.list" ]; then
    repos_list_file="repos-to-clone.list"
  else
    repos_list_file="repos.list"
  fi
  DEBUG=false
  DEBUG_FILE=""
  TEMP_DIR=""
  
  # Argument parsing
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--file)
        shift
        [ "$#" -gt 0 ] && repos_list_file="$1" && shift || { usage; exit 1; }
        ;;
      -d|--debug)
        DEBUG=true
        shift
        ;;
      --debug-file)
        DEBUG=true
        shift
        # Check if next arg exists and is not a flag
        if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
          DEBUG_FILE="$1"
          shift
        else
          # Auto-generate debug file securely
          TEMP_DIR=$(get_temp_dir)
          DEBUG_FILE=$(mktemp "${TEMP_DIR}/repos-workspace-debug-XXXXXX")
        fi
        ;;
      -h|--help)
        usage; exit 0
        ;;
      *)
      printf "Unknown argument: %s\n" "$1"
        usage
        exit 1
        ;;
    esac
  done

  # Set up debug file descriptor if needed
  if [ -n "$DEBUG_FILE" ]; then
    exec 3>>"$DEBUG_FILE"
  printf "vscode-workspace-add.sh debug output will be appended to: %s\n" "$DEBUG_FILE" >&2
  else
    # Redirect FD 3 to stderr by default
    exec 3>&2
  fi

  debug "=== vscode-workspace-add.sh Debug Session Started ==="
  debug "Repository list file: $repos_list_file"

  if [ ! -f "$repos_list_file" ]; then
    printf "Repository list file '%s' not found.\n" "$repos_list_file"
    exit 1
  fi

  [[ "$DEBUG" == true ]] && printf "[DEBUG] Using repo list file: %s\n" "$repos_list_file" >&2

  local current_dir workspace_file paths_list
  current_dir="$(pwd)"
  workspace_file="$(get_workspace_file "$current_dir")"
  
  [[ "$DEBUG" == true ]] && printf "[DEBUG] Workspace file: %s\n" "$workspace_file" >&2
  [[ "$DEBUG" == true ]] && printf "[DEBUG] Current dir: %s\n" "$current_dir" >&2

  paths_list="$(build_paths_list "$repos_list_file" "$current_dir" "$DEBUG")"

  update_workspace_file "$workspace_file" "$paths_list"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"

  debug "=== vscode-workspace-add.sh Debug Session Ended ==="

  # Close debug file descriptor if opened
  if [ -n "$DEBUG_FILE" ]; then
    exec 3>&-
  fi
fi
