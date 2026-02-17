#!/usr/bin/env bash
# vscode-workspace-add.sh — VS Code workspace updater for multi-repo / multi-branch setups
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# Behaviour:
#   • Lines starting with "@<branch>" inherit a "fallback repo":
#       - Initially: the CURRENT repo's remote (the repo that contains repos.list).
#       - After each clone line: fallback updates to the repo used/implied by that line.
#   • "@<branch>" resolves to a worktree path by default.
#   • Per-line opt-out: add "--no-worktree" or "-n" to treat @branch as a clone instead.
#
# Examples (repos.list):
#   @data-tidy data-tidy                 # uses current repo as fallback (worktree path)
#   SATVILab/projr                       # fallback → SATVILab/projr
#   @dev                                 # worktree path on SATVILab/projr
#   @dev-miguel                          # worktree path on SATVILab/projr
#   SATVILab/Analysis@test               # fallback → SATVILab/Analysis
#   @tweak                               # worktree path on SATVILab/Analysis
#   @dev-2                               # worktree path on SATVILab/Analysis

set -e

usage() {
  cat <<EOF
Usage: $0 [options]

Options:
  -f, --file <file>       Specify the repository list file (default: 'repos.list').
  -d, --debug             Enable debug output (shows path calculations).
  -h, --help              Display this help message.

Each line in the repository list file can be in one of three formats:

1) Clone a repo (default branch, or all branches with -a)
   owner/repo [target_directory] [-a|--all-branches]
   https://host/owner/repo [target_directory] [-a|--all-branches]

2) Clone exactly one branch
   owner/repo@branch [target_directory]

3) Create a worktree from the current fallback repo
   @branch [target_directory] [--no-worktree|-n]

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
  @analysis analysis                   # worktree off current repo
  SATVILab/stimgate                    # fallback updates
  @dev  stimgate-dev                   # worktree off SATVILab/stimgate
EOF
}

# --- Update workspace with jq ---
update_with_jq() {
  local workspace_file="$1"
  local paths_list="$2"
  local folders_json

  # build an array of {path: "..."} objects
  folders_json=$(printf '%s\n' "$paths_list" \
    | jq -R . \
    | jq -s '[ .[] | { path: . } ]'
  )

  if [ ! -f "$workspace_file" ]; then
    # create a brand-new workspace file
    jq --null-input --argjson folders "$folders_json" \
      '{ folders: $folders }' \
      > "$workspace_file"
  else
    # merge into existing file: set .folders = $folders
    tmp="$(mktemp)"
    jq --argjson folders "$folders_json" \
       '.folders = $folders' \
       "$workspace_file" > "$tmp" \
      && mv "$tmp" "$workspace_file"
  fi

  echo "Updated '$workspace_file' with jq."
}

# --- Update workspace with Python ---
PYTHON_UPDATE_SCRIPT=$(cat <<'PYCODE'
import sys, json, os
ws = sys.argv[1]
paths = [line for line in os.environ['PATHS_LIST'].splitlines() if line.strip()]
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
  PATHS_LIST="$paths_list" python - "$workspace_file" <<<"$PYTHON_UPDATE_SCRIPT"
  echo "Updated '$workspace_file' with Python."
}

update_with_python3() {
  local workspace_file="$1"
  local paths_list="$2"
  PATHS_LIST="$paths_list" python3 - "$workspace_file" <<<"$PYTHON_UPDATE_SCRIPT"
  echo "Updated '$workspace_file' with Python3."
}

update_with_py() {
  local workspace_file="$1"
  local paths_list="$2"
  PATHS_LIST="$paths_list" py - "$workspace_file" <<<"$PYTHON_UPDATE_SCRIPT"
  echo "Updated '$workspace_file' with py launcher."
}


# --- Update workspace with Rscript (jsonlite) ---
RSCRIPT_UPDATE=$(cat <<'ENDRSCRIPT'
args <- commandArgs(trailingOnly=TRUE)
ws <- args[1]

# Read and clean paths list
paths <- strsplit(Sys.getenv("PATHS_LIST"), "\n", fixed=TRUE)[[1]]
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
ENDRSCRIPT
)

update_with_rscript() {
  local workspace_file="$1"
  local paths_list="$2"
  PATHS_LIST="$paths_list" Rscript -e "$RSCRIPT_UPDATE" "$workspace_file"
  echo "Updated '$workspace_file' with Rscript."
}




get_workspace_file() {
  # Prefer lower-case, but use CamelCase if that's all there is
  local current_dir="$1"
  local workspace_file="$current_dir/entire-project.code-workspace"
  local workspace_file_camel="$current_dir/EntireProject.code-workspace"
  if [ -f "$workspace_file" ]; then
    echo "$workspace_file"
  elif [ -f "$workspace_file_camel" ]; then
    echo "$workspace_file_camel"
  else
    # If neither exists, will create lower-case one by default
    echo "$workspace_file"
  fi
}

spec_to_repo_name() {
  # Extract repo name from owner/repo or https URL
  local spec="$1"
  case "$spec" in
    https://*)
      spec="${spec%.git}"
      basename "$spec"
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

build_paths_list() {
  local repos_list_file="$1"
  local current_dir="$2"
  local debug="${3:-false}"
  local parent_dir
  parent_dir="$(dirname "$current_dir")"
  
  local paths_list="."
  local line trimmed first target_dir branch repo_spec repo_no_ref ref
  local fallback_repo_name repo_name is_worktree no_worktree repo_path relative_repo_path
  
  # --- Planning phase: count references per repo ---
  declare -a plan_repo_names=()
  declare -a plan_ref_counts=()
  
  local plan_repo_idx plan_repo_name plan_fallback_name no_worktree
  
  # Initialize fallback to current repo
  plan_fallback_name="$(basename "$current_dir")"
  
  [[ "$debug" == true ]] && echo "[DEBUG] Planning phase: counting references" >&2
  [[ "$debug" == true ]] && echo "[DEBUG] Planning fallback starts as: $plan_fallback_name" >&2
  
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in \#*|"") continue ;; esac
    case "$trimmed" in *" # "*) trimmed="${trimmed%% # *}" ;; *" #"*) trimmed="${trimmed%% #*}" ;; esac
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"; trimmed=${trimmed%$'\r'}
    [ -z "$trimmed" ] && continue
    
    set -f
    set -- $trimmed
    [ "$#" -eq 0 ] && { set +f; continue; }
    
    first="$1"; shift
    case "$first" in
      @*)
        # Worktree line: count as reference to fallback repo if not --no-worktree
        no_worktree=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -n|--no-worktree) no_worktree=1 ;;
          esac
          shift
        done
        
        if [ "$no_worktree" -eq 0 ]; then
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
          [[ "$debug" == true ]] && echo "[DEBUG]   Plan: worktree on fallback=$plan_fallback_name, count=${plan_ref_counts[${#plan_ref_counts[@]}-1]}" >&2
        fi
        # Note: worktree lines don't change the fallback
        ;;
      *)
        # Clone line: extract repo name
        repo_spec="$first"
        case "$repo_spec" in
          *@*) repo_no_ref="${repo_spec%@*}" ;;
          *)   repo_no_ref="$repo_spec" ;;
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
        [[ "$debug" == true ]] && echo "[DEBUG]   Plan: clone repo=$plan_repo_name, count=${plan_ref_counts[${#plan_ref_counts[@]}-1]}" >&2
        
        # Update fallback for subsequent lines
        plan_fallback_name="$plan_repo_name"
        [[ "$debug" == true ]] && echo "[DEBUG]   Plan: fallback updated to $plan_fallback_name" >&2
        ;;
    esac
    set +f
  done < "$repos_list_file"
  
  [[ "$debug" == true ]] && echo "[DEBUG] Planning complete" >&2
  
  # --- Main processing: build paths ---
  # Initialize fallback to current repo (the one containing repos.list)
  fallback_repo_name="$(basename "$current_dir")"
  [[ "$debug" == true ]] && echo "[DEBUG] Initial fallback repo: $fallback_repo_name" >&2

  while IFS= read -r line || [ -n "$line" ]; do
    # Trim and skip comments/blank lines
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in \#*|"") continue ;; esac
    case "$trimmed" in *" # "*) trimmed="${trimmed%% # *}" ;; *" #"*) trimmed="${trimmed%% #*}" ;; esac
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"; trimmed=${trimmed%$'\r'}
    [ -z "$trimmed" ] && continue
    
    [[ "$debug" == true ]] && echo "[DEBUG] Processing line: $trimmed" >&2

    # Parse the line (word splitting is intentional)
    set -f
    # shellcheck disable=SC2086
    set -- $trimmed
    [ "$#" -eq 0 ] && { set +f; continue; }
    
    first="$1"; shift
    target_dir=""
    is_worktree=0
    no_worktree=0
    
    case "$first" in
      @*)
        # Worktree line: @branch [target_dir] [--no-worktree|-n]
        branch="${first#@}"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -n|--no-worktree) no_worktree=1 ;;
            -a|--all-branches) ;; # ignore for path calculation
            -*)
              ;; # ignore unknown options
            *)
              if [ -z "$target_dir" ]; then
                target_dir="$1"
              fi
              ;;
          esac
          shift
        done
        
        # Determine if this is a worktree or clone
        if [ "$no_worktree" -eq 1 ]; then
          is_worktree=0
        else
          is_worktree=1
        fi
        
        if [ "$is_worktree" -eq 1 ]; then
          # Worktree path: ../<fallback_repo>-<branch> or ../<target_dir>
          if [ -n "$target_dir" ]; then
            repo_path="$parent_dir/$target_dir"
          else
            local safe_branch; safe_branch="$(sanitize_branch_name "$branch")"
            repo_path="$parent_dir/${fallback_repo_name}-${safe_branch}"
          fi
          [[ "$debug" == true ]] && echo "[DEBUG]   @branch (worktree): branch=$branch, fallback=$fallback_repo_name, path=$repo_path" >&2
        else
          # Clone path: same as owner/repo@branch
          if [ -n "$target_dir" ]; then
            repo_path="$parent_dir/$target_dir"
          else
            local safe_branch; safe_branch="$(sanitize_branch_name "$branch")"
            repo_path="$parent_dir/${fallback_repo_name}-${safe_branch}"
          fi
          [[ "$debug" == true ]] && echo "[DEBUG]   @branch (clone): branch=$branch, fallback=$fallback_repo_name, path=$repo_path" >&2
        fi
        ;;
      *)
        # Clone line: owner/repo[@branch] [target_dir]
        repo_spec="$first"
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -a|--all-branches) ;; # ignore for path calculation
            -n|--no-worktree) ;; # ignore on clone lines
            -*)
              ;; # ignore unknown options
            *)
              if [ -z "$target_dir" ]; then
                target_dir="$1"
              fi
              ;;
          esac
          shift
        done
        
        # Split repo_spec into repo and optional branch
        case "$repo_spec" in
          *@*) repo_no_ref="${repo_spec%@*}"; ref="${repo_spec##*@}" ;;
          *)   repo_no_ref="$repo_spec"; ref="" ;;
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
        [[ "$debug" == true ]] && echo "[DEBUG]   Clone line: repo=$repo_name, path=$repo_path, new fallback=$fallback_repo_name" >&2
        ;;
    esac
    set +f

    # Calculate relative path from current_dir to repo_path
    if command -v realpath >/dev/null 2>&1 && realpath --help 2>&1 | grep -q -- --relative-to; then
      relative_repo_path="$(realpath --relative-to="$current_dir" "$repo_path" 2>/dev/null || printf '%s\n' "$repo_path")"
    else
      # Manual relative path calculation (for systems without realpath)
      # Since repo_path is in parent_dir and current_dir is inside parent_dir,
      # the relative path is always ../basename
      relative_repo_path="../$(basename "$repo_path")"
    fi

    [ "$relative_repo_path" = "." ] && continue
    paths_list="${paths_list}"$'\n'"$relative_repo_path"
  done < "$repos_list_file"

  printf '%s\n' "$paths_list"
}

update_workspace_file() {
  local workspace_file="$1"
  local paths_list="$2"
  [ -n "$workspace_file" ] || { echo "update_workspace_file: missing workspace_file" >&2; exit 1; }
  [ -n "$paths_list" ]   || { echo "update_workspace_file: missing paths_list"   >&2; exit 1; }


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
    echo "Error: none of jq, python, python3, py, or Rscript found. Cannot update workspace." >&2
    exit 1
  fi
}

main() {
  local repos_list_file DEBUG
  if [ ! -f "repos.list" ] && [ -f "repos-to-clone.list" ]; then
    repos_list_file="repos-to-clone.list"
  else
    repos_list_file="repos.list"
  fi
  DEBUG=false
  
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
      -h|--help)
        usage; exit 0
        ;;
      *)
        echo "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done

  if [ ! -f "$repos_list_file" ]; then
    echo "Repository list file '$repos_list_file' not found."
    exit 1
  fi

  [[ "$DEBUG" == true ]] && echo "[DEBUG] Using repo list file: $repos_list_file" >&2

  local current_dir workspace_file paths_list
  current_dir="$(pwd)"
  workspace_file="$(get_workspace_file "$current_dir")"
  
  [[ "$DEBUG" == true ]] && echo "[DEBUG] Workspace file: $workspace_file" >&2
  [[ "$DEBUG" == true ]] && echo "[DEBUG] Current dir: $current_dir" >&2

  paths_list="$(build_paths_list "$repos_list_file" "$current_dir" "$DEBUG")"

  update_workspace_file "$workspace_file" "$paths_list"
}

main "$@"
