#!/usr/bin/env bash
# clone-repos.sh — Multi-repo / multi-branch cloner with worktree-by-default for @branch
# Portable: Bash ≥3.2 (macOS default), Linux, WSL, Git Bash
#
# Behaviour:
#   • Lines starting with "@<branch>" inherit a "fallback repo":
#       - Initially: the CURRENT repo's remote (the repo that contains repos.list).
#       - After each line: fallback updates to the repo used/implied by that line.
#   • "@<branch>" creates a GIT WORKTREE by default.
#   • Per-line opt-out: add "--no-worktree" or "-n" to clone instead of worktree.
#
# Examples (repos.list):
#   @data-tidy data-tidy                 # uses current repo as fallback (worktree)
#   SATVILab/projr                       # fallback → SATVILab/projr
#   @dev                                 # worktree on SATVILab/projr
#   @dev-miguel                          # worktree on SATVILab/projr
#   SATVILab/Analysis@test               # fallback → SATVILab/Analysis
#   @tweak                               # worktree on SATVILab/Analysis
#   @dev-2                               # worktree on SATVILab/Analysis
#
# Notes:
#   • Clone lines still accept "-a|--all-branches" (single-branch is default).
#   • @branch worktrees are always anchored off a LOCAL base directory:
#       - If a full clone exists (or is planned later), that path is the base.
#       - Otherwise the first single-branch clone becomes the base.
#     No side “-base” directories are created.

set -Eeo pipefail
# Never prompt for credentials (prevents stdin reads that can kill the loop)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
: "${GIT_SSH_COMMAND:=ssh -oBatchMode=yes}"
trace() { printf '▶ %s\n' "$*" >&2; }
trap '' ERR

git() { command git "$@" </dev/null; }

# --- Planning & state (Bash 3.2-friendly) -----------------------------------
# Remotes we've seen (normalised https), and where their local base lives
declare -a SEEN_REMOTES=()
declare -a REMOTE_LOCAL_PATH=()

# --- Counters ---------------------------------------------------------------
# 0 = success, 2 = benign skip, 1 = real error
declare -i CNT_TOTAL=0
declare -i CNT_CLONED_FULL=0
declare -i CNT_CLONED_BRANCH=0
declare -i CNT_WORKTREE_ADDED=0
declare -i CNT_SKIPPED=0
declare -i CNT_ERRORS=0

# Plan: for each remote, whether a full clone line exists anywhere,
# and what the preferred base dir name should be for the full clone.
declare -a PLAN_REMOTES=()
declare -a PLAN_HAS_FULL=()     # 0/1
declare -a PLAN_BASE_NAME=()    # base directory name (e.g. "projr" or an explicit target)
declare -a PLAN_REF_COUNT=()    # count of references to this remote (for branch suffix logic)

# Last clone destination (used to set fallback base)
CLONE_DEST=""

remote_index() { # echo index or -1
  local needle="$1" i
  for i in "${!SEEN_REMOTES[@]}"; do
    [ "${SEEN_REMOTES[$i]}" = "$needle" ] && { echo "$i"; return; }
  done
  echo -1
}

remember_remote() { # remote https, local path
  local remote="$1" path="$2" idx
  idx="$(remote_index "$remote")"
  if [ "$idx" -ge 0 ]; then
    [ -z "${REMOTE_LOCAL_PATH[$idx]}" ] && [ -n "$path" ] && REMOTE_LOCAL_PATH[$idx]="$path"
  else
    SEEN_REMOTES+=("$remote")
    REMOTE_LOCAL_PATH+=("$path")
  fi
}

plan_index() { # echo index in PLAN_REMOTES or -1
  local needle="$1" i
  for i in "${!PLAN_REMOTES[@]}"; do
    [ "${PLAN_REMOTES[$i]}" = "$needle" ] && { echo "$i"; return; }
  done
  echo -1
}

plan_remember_remote() { # remote https, has_full(0/1), base_name_or_empty
  local r="$1" has="$2" base="$3" idx
  idx="$(plan_index "$r")"
  if [ "$idx" -ge 0 ]; then
    # Once true, stays true; preserve first explicit base name if provided
    [ "${PLAN_HAS_FULL[$idx]}" -eq 0 ] && [ "$has" -eq 1 ] && PLAN_HAS_FULL[$idx]=1
    if [ -n "$base" ] && [ -z "${PLAN_BASE_NAME[$idx]}" ]; then
      PLAN_BASE_NAME[$idx]="$base"
    fi
    # Increment reference count
    PLAN_REF_COUNT[$idx]=$((${PLAN_REF_COUNT[$idx]} + 1))
  else
    PLAN_REMOTES+=("$r")
    PLAN_HAS_FULL+=("$has")
    PLAN_BASE_NAME+=("$base")
    PLAN_REF_COUNT+=("1")
  fi
}

plan_has_full() { # remote https -> 0/1
  local idx; idx="$(plan_index "$1")"
  [ "$idx" -ge 0 ] && echo "${PLAN_HAS_FULL[$idx]}" || echo 0
}

plan_base_name() { # remote https -> base dir name (fallback to repo name)
  local r="$1" idx name
  idx="$(plan_index "$r")"
  if [ "$idx" -ge 0 ]; then
    name="${PLAN_BASE_NAME[$idx]}"
    if [ -n "$name" ]; then echo "$name"; return; fi
  fi
  # default to repo basename from https
  echo "${r##*/}"
}

plan_ref_count() { # remote https -> reference count (default 0)
  local idx; idx="$(plan_index "$1")"
  [ "$idx" -ge 0 ] && echo "${PLAN_REF_COUNT[$idx]}" || echo 0
}

ensure_base_exists() { # remote https, base_abs_path, debug
  local remote="$1" base="$2" debug="$3"

  [[ "$debug" == true ]] && echo "ensure_base_exists: checking base '$base' for remote '$remote'" >&2

  # Treat as Git repo if rev-parse says so (works for .git dirs *and* .git files/worktrees)
  if git -C "$base" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [[ "$debug" == true ]] && echo "ensure_base_exists: base '$base' already exists as git repo" >&2
    return 0  # already a git repo: OK
  fi

  # If the path exists and is non-empty but not a git repo, signal a benign per-line failure
  if [ -e "$base" ] && [ -n "$(ls -A "$base" 2>/dev/null)" ]; then
    echo "Error: intended base '$base' exists and is not a Git repo (non-empty). Skipping." >&2
    [[ "$debug" == true ]] && echo "ensure_base_exists: returning error code 2" >&2
    return 2
  fi

  # Create dir if needed and clone a proper base
  [[ "$debug" == true ]] && echo "ensure_base_exists: creating base directory and cloning" >&2
  mkdir -p "$base"
  echo "Priming base clone for $remote → $base"
  if ! git clone "$remote" "$base" </dev/null; then
    echo "Error: failed to clone '$remote' into '$base'." >&2
    [[ "$debug" == true ]] && echo "ensure_base_exists: clone failed, returning error code 3" >&2
    return 3
  fi
  CNT_CLONED_FULL=$((CNT_CLONED_FULL + 1))
  [[ "$debug" == true ]] && echo "ensure_base_exists: base clone successful" >&2

  return 0
}

# --- Prerequisites -----------------------------------------------------------
check_prerequisites() {
  local debug="$1"
  [[ "$debug" == true ]] && echo "Checking prerequisites..." >&2
  for cmd in git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: '$cmd' is required but not found in PATH." >&2
      exit 1
    fi
  done
  [[ "$debug" == true ]] && echo "All prerequisites met." >&2
  return 0
}

check_non_interactive_auth() {
  local debug="$1"
  [[ "$debug" == true ]] && echo "Checking for non-interactive authentication..." >&2
  
  local has_auth=0
  
  # 1. Check for GH_TOKEN
  if [ -n "${GH_TOKEN:-}" ]; then
    [[ "$debug" == true ]] && echo "✓ GH_TOKEN is set" >&2
    has_auth=1
  fi
  
  # 2. Check for gh CLI authentication
  if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
      [[ "$debug" == true ]] && echo "✓ gh CLI is authenticated" >&2
      has_auth=1
    fi
  fi
  
  # 3. Check for SSH agent (for git@github.com URLs)
  if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK}" ]; then
    if command -v ssh-add >/dev/null 2>&1; then
      if ssh-add -l >/dev/null 2>&1; then
        [[ "$debug" == true ]] && echo "✓ SSH agent has keys" >&2
        has_auth=1
      fi
    fi
  fi
  
  # 4. Check for Git credential helper (e.g., Git Credential Manager)
  if git config --get credential.helper >/dev/null 2>&1; then
    [[ "$debug" == true ]] && echo "✓ Git credential helper configured" >&2
    has_auth=1
  fi
    
  # If no authentication method is available, fail early with helpful message
  if [ "$has_auth" -eq 0 ]; then
    cat >&2 <<'EOF'
Error: No non-interactive GitHub authentication available.

This script runs in non-interactive mode and requires credentials for cloning/pushing.

Please set up one of the following:

1. GitHub Token:
   export GH_TOKEN="your_github_token"
   
   For Codespaces, add GH_TOKEN as a Codespaces secret:
   https://github.com/settings/codespaces

2. GitHub CLI:
   gh auth login
   
3. SSH Agent (for SSH URLs):
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/id_rsa

For more details, see: README.md
EOF
    return 1
  fi
  
  [[ "$debug" == true ]] && echo "Non-interactive authentication check passed." >&2
  return 0
}

# --- Usage -------------------------------------------------------------------
usage() {
  cat <<'EOF'
Usage: clone-repos.sh [--file <repo-list>] [--debug] [--help]

Each non-empty, non-comment line in <repo-list> is one instruction. There are three kinds:

1) Clone a repo (default branch, or all branches with -a)
   owner/repo [target_directory] [-a|--all-branches]
   https://host/owner/repo [target_directory] [-a|--all-branches]
   Behaviour:
     • Clones the repo into target_directory (or ./<repo> if omitted).
     • By default uses --single-branch on the remote's default branch.
       Add -a|--all-branches to fetch all remote branches.
     • Updates the “fallback repo” to this newly cloned local directory.
       Subsequent @branch lines will create worktrees off this directory.

2) Clone exactly one branch
   owner/repo@branch [target_directory]
   Behaviour:
     • Clones only that branch (single-branch checkout) into target_directory
       (or ./<repo> if omitted).
     • If the branch does not exist remotely, the script clones the default
       branch, creates <branch> locally, and pushes it upstream with tracking.
     • Updates the fallback repo to this newly cloned local directory.

3) Create a worktree from the current fallback repo
   @branch [target_directory] [--no-worktree|-n]
   Behaviour (default):
     • Creates a git worktree for <branch> anchored at the current fallback
       repo’s LOCAL directory. No side “<repo>-base” directories are created.
     • Destination is ../<repo>-<branch> by default, or ../<target_directory> if given.
     • If the branch does not exist locally but exists on origin, a tracking
       worktree is created. If it does not exist on origin, the branch is created
       from origin/<default>, then pushed with upstream set.
   Opt-out:
     • Add --no-worktree (or -n) to clone the fallback repo’s @branch instead
       of creating a worktree.

Fallback repo rules
  • Initially, the fallback repo is the repository containing <repo-list>
    (i.e. the current directory when you run this script).
  • After any successful clone line (1 or 2), the fallback repo becomes that
    newly cloned directory. @branch lines then hang worktrees off it.
  • @branch lines themselves do not change the fallback.

Conventions and paths
  • target_directory is created under the PARENT of the current directory.
    For example, running in /workspaces/analysis:
      - owner/repo → /workspaces/repo
      - @dev my-branch → /workspaces/<repo>-my-branch
  • Existing non-empty destinations cause an error (to avoid clobbering).
  • You cannot check out the same branch into two worktrees at once; if an
    identical worktree already exists, the script no-ops that line.

Examples
  # Worktrees off the current repo (the one containing repos.list)
  @analysis analysis
  @paper    paper

  # Clone an external repo (default branch), then make worktrees on it
  SATVILab/stimgate
  @dev  stimgate-dev
  @main stimgate-main

  # Clone only a specific branch (no worktree)
  SATVILab/UtilsCytoRSV@release utils-rsv-release

Options
  -f, --file <repo-list>   Use an alternate repo list file (default: repos.list,
                           or repos-to-clone.list if repos.list is absent).
  -d, --debug.             Enable debug tracing.
  -h, --help               Show this help and exit.
EOF
}

# --- Normalisation helpers ---------------------------------------------------
normalise_remote_to_https() {
  # Convert a remote URL to https://host/owner/repo (no .git)
  # Normalize file:// and absolute paths to absolute path form
  local url="$1" host path
  case "$url" in
    file://*)
      # Convert file:///path to /path
      url="${url#file://}"
      url="${url%.git}"
      printf '%s\n' "$url"
      ;;
    /*)
      url="${url%.git}"
      printf '%s\n' "$url"
      ;;
    https://*)
      url="${url%.git}"
      printf '%s\n' "$url"
      ;;
    ssh://git@*)
      url="${url#ssh://git@}"
      host="${url%%/*}"
      path="${url#*/}"
      printf 'https://%s/%s\n' "$host" "${path%.git}"
      ;;
    git@*:* )
      host="${url#git@}"; host="${host%%:*}"
      path="${url#*:}";   path="${path%.git}"
      printf 'https://%s/%s\n' "$host" "$path"
      ;;
    *)
      printf '%s\n' "$url"
      ;;
  esac
}

spec_to_https() {
  # owner/repo → https://github.com/owner/repo ; https stays https
  # file://... → /... (normalized to absolute path)
  # /absolute/path → stays /absolute/path
  local spec="$1"
  case "$spec" in
    file://*)
      # Convert file:///path to /path for consistency
      spec="${spec#file://}"
      printf '%s\n' "${spec%.git}"
      ;;
    https://*) printf '%s\n' "${spec%.git}" ;;
    /*) printf '%s\n' "${spec%.git}" ;;
    */*)
      # Only convert to GitHub URL if it looks like owner/repo (not a path)
      if [[ "$spec" =~ ^[^/]+/[^/]+(@.*)?$ ]]; then
        printf 'https://github.com/%s\n' "${spec%.git}"
      else
        printf '%s\n' "${spec%.git}"
      fi
      ;;
    *)         printf '%s\n' "$spec" ;;
  esac
}

repo_basename_from_https() {
  local url="$1"
  url="${url%/}"
  printf '%s\n' "${url##*/}"
}

# Sanitize branch name for use in directory paths
# Replaces forward slashes with dashes to avoid nested directories
sanitize_branch_name() {
  local branch="$1"
  printf '%s\n' "${branch//\//-}"
}

# --- Git helpers -------------------------------------------------------------
# Returns origin URL for a repo dir, or fails cleanly (no ERR trap)
safe_get_origin_url() {
  local dir="$1" url
  url="$(git -C "$dir" remote get-url origin 2>/dev/null)" ||
  url="$(git -C "$dir" config --get remote.origin.url 2>/dev/null)" || return 1
  printf '%s\n' "$url"
}

# Check if repos.list contains any non-local remotes (requires GitHub auth)
has_non_local_remotes() {
  local file="$1"
  while IFS= read -r line || [ -n "$line" ]; do
    # Skip comments and blank lines
    case "$line" in \#*|"") continue ;; esac
    # Remove inline comments
    case "$line" in *" # "*) line="${line%% # *}" ;; *" #"*) line="${line%% #*}" ;; esac
    # Trim whitespace
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    line=${line%$'\r'}
    [ -z "$line" ] && continue
    
    # Extract first token
    set -f
    set -- $line
    [ "$#" -eq 0 ] && { set +f; continue; }
    local first="$1"
    set +f
    
    # Skip @branch lines (use fallback repo)
    case "$first" in @*) continue ;; esac
    
    # Extract repo spec (remove @branch if present)
    local repo_spec="${first%@*}"
    
    # Check if it's a local remote
    case "$repo_spec" in
      file://*|/*) continue ;;  # Local path
      */*)
        # Check if it looks like owner/repo (GitHub format)
        if [[ "$repo_spec" =~ ^[^/]+/[^/]+$ ]]; then
          return 0  # Found non-local remote
        fi
        ;;
      https://*)
        return 0  # Found non-local remote
        ;;
    esac
  done <"$file"
  return 1  # All remotes are local
}

get_current_repo_remote_https() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not inside a Git working tree; cannot derive fallback repo." >&2
    exit 1
  }

  local url="" first=""
  if git remote | grep -qx 'origin'; then
    if ! url="$(git remote get-url --push origin 2>/dev/null)"; then
      url="$(git remote get-url origin 2>/dev/null || true)"
    fi
  fi

  if [ -z "$url" ]; then
    if first="$(git remote 2>/dev/null | head -n1)"; then
      if ! url="$(git remote get-url --push "$first" 2>/dev/null)"; then
        url="$(git remote get-url "$first" 2>/dev/null || true)"
      fi
    fi
  fi

  [ -z "$url" ] && { echo "Error: no Git remotes found in the current repository." >&2; exit 1; }
  normalise_remote_to_https "$url"
}

default_remote_branch() {
  local base="$1" ref=""
  if ref="$(git -C "$base" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"; then
    printf '%s\n' "${ref#origin/}"
  else
    printf 'main\n'
  fi
}

local_branch_exists()   { git -C "$1" rev-parse --verify --quiet "refs/heads/$2" >/dev/null; }
remote_branch_exists()  { git -C "$1" rev-parse --verify --quiet "refs/remotes/origin/$2" >/dev/null; }

# Ensure wildcard fetch refspec exists for origin remote
# This is needed for branch tracking to work in single-branch clones
ensure_wildcard_fetch_refspec() {
  local base="$1"
  local wildcard_refspec="+refs/heads/*:refs/remotes/origin/*"
  
  # Check if wildcard refspec already exists
  if git -C "$base" config --get-all remote.origin.fetch | grep -qF "$wildcard_refspec"; then
    return 0
  fi
  
  # Add wildcard refspec (does not remove existing refspecs)
  git -C "$base" config --add remote.origin.fetch "$wildcard_refspec" 2>/dev/null || true
}

find_worktree_for_branch() {
  local base="$1" branch="$2" line=""
  if line="$(git -C "$base" worktree list 2>/dev/null | grep " \[$branch\]" | head -n1)"; then
    printf '%s\n' "${line%% *}"
  fi
}

# --- Parsing -----------------------------------------------------------------
# Returns: repo_spec \x1f target_dir \x1f all_branches \x1f is_worktree
parse_effective_line() {
  set -f
  local line="$1" fallback_repo_https="$2"
  local first target_dir="" all_branches=0 is_worktree=0 no_worktree=0

  set -- $line
  [ "$#" -eq 0 ] && { printf '%s\x1f%s\x1f%s\x1f%s\n' "" "" "0" "0"; set +f; return 0; }

  first="$1"; shift
  case "$first" in
    @*)
      local branch="${first#@}"
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -n|--no-worktree) no_worktree=1 ;;
          -a|--all-branches) all_branches=1 ;;  # harmless for worktrees
          -*)
            echo "Warning: ignoring unknown option '$1' on line: $line" >&2 ;;
          *)
            if [ -z "$target_dir" ]; then target_dir="$1"
            else echo "Error: multiple target directories on one line: $line" >&2; set +f; return 1
            fi ;;
        esac
        shift
      done
      [ -z "$fallback_repo_https" ] && { echo "Error: no fallback repo available for '$line'."; set +f; return 1; }
      is_worktree=$(( no_worktree ? 0 : 1 ))
      printf '%s@%s\x1f%s\x1f%s\x1f%s\n' "$fallback_repo_https" "$branch" "$target_dir" "$all_branches" "$is_worktree"
      ;;
    *)
      local repo_spec="$first"
      while [ "$#" -gt 0 ]; do
        case "$1" in
          -a|--all-branches) all_branches=1 ;;
          -n|--no-worktree)  echo "Warning: '--no-worktree' ignored on clone line: $line" >&2 ;;
          -*)
            echo "Warning: ignoring unknown option '$1' on line: $line" >&2 ;;
          *)
            if [ -z "$target_dir" ]; then target_dir="$1"
            else echo "Error: multiple target directories on one line: $line" >&2; set +f; return 1
            fi ;;
        esac
        shift
      done
      is_worktree=0
      printf '%s\x1f%s\x1f%s\x1f%s\n' "$repo_spec" "$target_dir" "$all_branches" "$is_worktree"
      ;;
  esac
  set +f
}

# --- Clone flow --------------------------------------------------------------
clone_one_repo() {
  local repo_spec="$1" target_dir="$2" base_dir="$3" all_branches="$4" debug="$5"

  [[ "$debug" == true ]] && echo "clone_one_repo: processing repo_spec='$repo_spec' target_dir='$target_dir'" >&2

  local repo_url_no_ref ref
  case "$repo_spec" in
    *@*) repo_url_no_ref="${repo_spec%@*}"; ref="${repo_spec##*@}" ;;
    *)   repo_url_no_ref="$repo_spec"; ref="" ;;
  esac
  [[ "$debug" == true ]] && echo "clone_one_repo: parsed repo_url_no_ref='$repo_url_no_ref' ref='$ref'" >&2

  local repo_url repo_dir
  case "$repo_url_no_ref" in
    file://*)
      repo_url="$repo_url_no_ref"
      repo_dir=$(basename "${repo_url_no_ref%.git}")
      ;;
    /*)
      repo_url="$repo_url_no_ref"
      repo_dir=$(basename "${repo_url_no_ref%.git}")
      ;;
    https://*)
      repo_url="$repo_url_no_ref"
      repo_dir=$(basename "${repo_url_no_ref%.git}")
      ;;
    */*)
      # Only convert to GitHub URL if it looks like owner/repo (not a path)
      if [[ "$repo_url_no_ref" =~ ^[^/]+/[^/]+$ ]]; then
        repo_url="https://github.com/$repo_url_no_ref"
        repo_dir="${repo_url_no_ref#*/}"
      else
        # Looks like a path with multiple slashes
        repo_url="$repo_url_no_ref"
        repo_dir=$(basename "${repo_url_no_ref%.git}")
      fi
      ;;
    *)
      echo "Error: invalid repo spec '$repo_spec'." >&2; return 1 ;;
  esac

  # Normalised https remote for lookup (owner/repo or url)
  local remote_https
  remote_https="$(spec_to_https "$repo_url_no_ref")"
  [[ "$debug" == true ]] && echo "clone_one_repo: remote_https='$remote_https'" >&2

  local dest
  if [ -n "$target_dir" ]; then
    dest="$base_dir/$target_dir"
    [[ "$debug" == true ]] && echo "clone_one_repo: using explicit target_dir, dest='$dest'" >&2
  elif [ -n "$ref" ] ; then
    # Single-branch clone with no explicit target dir:
    # If there are multiple references to this repo (ref_count > 1),
    # put it in <repo>-<branch>; otherwise let it take <repo>.
    local ref_count; ref_count="$(plan_ref_count "$remote_https")"
    if [ "$ref_count" -gt 1 ]; then
      local safe_ref; safe_ref="$(sanitize_branch_name "$ref")"
      dest="$base_dir/${repo_dir}-${safe_ref}"
      [[ "$debug" == true ]] && echo "clone_one_repo: single-branch clone (multiple refs: $ref_count), dest='$dest'" >&2
    else
      dest="$base_dir/$repo_dir"
      [[ "$debug" == true ]] && echo "clone_one_repo: single-branch clone (single ref), dest='$dest'" >&2
    fi
  else
    # Full clone (no @branch)
    dest="$base_dir/$repo_dir"
    [[ "$debug" == true ]] && echo "clone_one_repo: full clone, dest='$dest'" >&2
  fi

  # 0) If destination already contains a Git repo, reuse it (only if it matches the intended remote)
  if [ -d "$dest/.git" ]; then
    [[ "$debug" == true ]] && echo "clone_one_repo: destination '$dest' already exists, checking remote" >&2
    local existing_remote="" existing_https=""
    if existing_remote="$(safe_get_origin_url "$dest")"; then
      existing_https="$(normalise_remote_to_https "$existing_remote")"
    else
      existing_https=""
    fi

    if [ -n "$existing_https" ] && [ "$existing_https" = "$remote_https" ]; then
      echo "Already exists: $dest (matches $remote_https)"
      [[ "$debug" == true ]] && echo "clone_one_repo: remote matches, skipping" >&2
      CLONE_DEST="$dest"
      remember_remote "$remote_https" "$dest"
      CNT_SKIPPED=$((CNT_SKIPPED + 1))
      return 2   # benign skip
    else
      echo "Skip: $dest is a Git repo for '$existing_https' (wanted '$remote_https'); leaving as-is."
      [[ "$debug" == true ]] && echo "clone_one_repo: remote mismatch, skipping" >&2
      CNT_SKIPPED=$((CNT_SKIPPED + 1))
      # Do NOT set CLONE_DEST or remember_remote here
      return 2   # benign skip
    fi
  fi
  # 1) Create the destination dir if needed
  [[ "$debug" == true ]] && echo "clone_one_repo: creating destination directory '$dest'" >&2
  mkdir -p "$dest"

  # 2) If the destination exists and is non-empty but not a Git repo, skip (don't abort the whole run)
  if [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    [[ "$debug" == true ]] && echo "clone_one_repo: destination is non-empty, checking if it's a git repo" >&2
    if [ -d "$dest/.git" ]; then
      echo "Already exists: $dest"
      [[ "$debug" == true ]] && echo "clone_one_repo: is a git repo, skipping" >&2
      CLONE_DEST="$dest"
      remember_remote "$remote_https" "$dest"
      CNT_SKIPPED=$((CNT_SKIPPED + 1))
      return 2
    else
      echo "Skip: $dest exists and is not empty (non-Git); leaving as-is."
      [[ "$debug" == true ]] && echo "clone_one_repo: not a git repo, skipping" >&2
      CNT_SKIPPED=$((CNT_SKIPPED + 1))
      # Do NOT set CLONE_DEST or remember_remote here
      return 2  # benign skip
    fi
  fi

  # If a branch ref was requested, check whether it exists on the remote.
  if [ -n "$ref" ]; then
    [[ "$debug" == true ]] && echo "clone_one_repo: checking if branch '$ref' exists on remote" >&2
    if git ls-remote --exit-code --heads "$repo_url" "$ref" >/dev/null 2>&1; then
      # Remote branch exists: clone it directly.
      [[ "$debug" == true ]] && echo "clone_one_repo: remote branch exists, cloning directly" >&2
      local clone_opts=()
      if [ "${all_branches:-0}" -eq 0 ]; then clone_opts=(--single-branch); fi
      clone_opts+=("--branch" "$ref")
      echo "Cloning $repo_url → $dest (branch $ref)"
      git clone "${clone_opts[@]}" "$repo_url" "$dest" </dev/null
      CNT_CLONED_BRANCH=$((CNT_CLONED_BRANCH + 1))
      CLONE_DEST="$dest"
      remember_remote "$remote_https" "$dest"
      [[ "$debug" == true ]] && echo "clone_one_repo: branch clone successful" >&2
    else
      # Remote branch does not exist: clone default branch, create and publish the new one.
      [[ "$debug" == true ]] && echo "clone_one_repo: remote branch not found, will create it" >&2
      local clone_opts=()
      if [ "${all_branches:-0}" -eq 0 ]; then clone_opts=(--single-branch); fi
      echo "Remote branch '$ref' not found on $repo_url; creating it."
      echo "Cloning default branch of $repo_url → $dest"
      git clone "${clone_opts[@]}" "$repo_url" "$dest" </dev/null
      CNT_CLONED_BRANCH=$((CNT_CLONED_BRANCH + 1))
      CLONE_DEST="$dest"
      remember_remote "$remote_https" "$dest"
      # Create the new branch locally and publish it upstream with tracking.
      [[ "$debug" == true ]] && echo "clone_one_repo: creating and pushing new branch '$ref'" >&2
      git -C "$dest" switch -c "$ref" </dev/null
      git -C "$dest" push -u origin HEAD:"$ref" </dev/null
      [[ "$debug" == true ]] && echo "clone_one_repo: new branch created and pushed" >&2
    fi
  else
    # No branch ref requested: normal clone (default branch or all branches).
    [[ "$debug" == true ]] && echo "clone_one_repo: performing full clone (no specific branch)" >&2
    local clone_opts=()
    if [ "${all_branches:-0}" -eq 0 ]; then clone_opts=(--single-branch); fi
    echo "Cloning $repo_url → $dest"
    git clone "${clone_opts[@]}" "$repo_url" "$dest" </dev/null
    CNT_CLONED_FULL=$((CNT_CLONED_FULL + 1))
    CLONE_DEST="$dest"
    remember_remote "$remote_https" "$dest"
    [[ "$debug" == true ]] && echo "clone_one_repo: full clone successful" >&2
  fi
  return 0
}

# --- Worktree flow -----------------------------------------------------------
create_worktree_for_branch() {
  # Args: base_path branch target_dir parent_dir debug
  local base="$1" branch="$2" target_dir="$3" parent_dir="$4" debug="$5"
  
  [[ "$debug" == true ]] && echo "create_worktree_for_branch: base='$base' branch='$branch' target_dir='$target_dir'" >&2
  
  [ -z "$branch" ] && { echo "Error: @branch requires a branch name."; return 1; }
  [ -z "$base" ] && { echo "Error: no fallback base path available for worktree."; return 1; }

  # Prune stale worktree references (e.g., from manually deleted directories)
  # This prevents errors like "branch is already used by worktree at <deleted-path>"
  [[ "$debug" == true ]] && echo "create_worktree_for_branch: pruning stale worktree references" >&2
  git -C "$base" worktree prune </dev/null || true

  # If this branch is already checked out in any worktree, skip
  [[ "$debug" == true ]] && echo "create_worktree_for_branch: checking if branch already checked out" >&2
  local existing_wt
  existing_wt="$(find_worktree_for_branch "$base" "$branch" || true)"
  if [ -n "$existing_wt" ]; then
    echo "Skip: branch '$branch' already checked out at $existing_wt"
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: branch already checked out, skipping" >&2
    CNT_SKIPPED=$((CNT_SKIPPED + 1))
    return 2
  fi

  local repo_base; repo_base="$(basename "$base")"
  local dest
  if [ -n "$target_dir" ]; then
    dest="$parent_dir/$target_dir"
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: using explicit target_dir, dest='$dest'" >&2
  else
    local safe_branch; safe_branch="$(sanitize_branch_name "$branch")"
    dest="$parent_dir/${repo_base}-${safe_branch}"
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: using default dest='$dest'" >&2
  fi

  if [ -d "$dest/.git" ]; then
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: destination already exists, checking branch" >&2
    if git -C "$dest" rev-parse --abbrev-ref HEAD >/dev/null 2>&1; then
      local curb; curb="$(git -C "$dest" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
      if [ "$curb" = "$branch" ]; then
        echo "Already exists: $dest (branch $branch)"
      else
        echo "Skip: $dest already exists (branch '$curb'); leaving as-is."
      fi
    else
      echo "Skip: $dest already exists and is a Git dir; leaving as-is."
    fi
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: destination exists, skipping" >&2
    CNT_SKIPPED=$((CNT_SKIPPED + 1))
    return 2  # benign skip
  fi

  [[ "$debug" == true ]] && echo "create_worktree_for_branch: fetching from origin" >&2
  git -C "$base" fetch --prune origin </dev/null

  [[ "$debug" == true ]] && echo "create_worktree_for_branch: creating destination directory" >&2
  mkdir -p "$dest"
  if [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    echo "Skip: destination '$dest' exists and is not empty; not touching it." >&2
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: destination non-empty, skipping" >&2
    CNT_SKIPPED=$((CNT_SKIPPED + 1))
    return 2  # benign skip
  fi

  if local_branch_exists "$base" "$branch"; then
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: local branch exists, adding worktree" >&2
    echo "Adding worktree $dest (existing local branch '$branch')"
    git -C "$base" worktree add "$dest" "$branch" </dev/null
    CNT_WORKTREE_ADDED=$((CNT_WORKTREE_ADDED + 1))
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: worktree added, setting upstream if needed" >&2
    if git -C "$base" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
      ensure_wildcard_fetch_refspec "$base"
      git -C "$dest" branch --set-upstream-to="origin/$branch" || true
    else
      git -C "$dest" push -u origin HEAD:"$branch" || true
    fi
  elif git -C "$base" ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    echo "Branch exists: $branch (on remote)"
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: branch exists on origin, tracking it" >&2
    echo "Adding worktree $dest (tracking origin/$branch)"
    # Ensure the remote-tracking ref exists even in single-branch clones
    git -C "$base" fetch origin "refs/heads/$branch:refs/remotes/origin/$branch" || true
    if git -C "$base" rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
      git -C "$base" worktree add -b "$branch" "$dest" "origin/$branch" </dev/null
      CNT_WORKTREE_ADDED=$((CNT_WORKTREE_ADDED + 1))
      ensure_wildcard_fetch_refspec "$base"
      git -C "$dest" branch --set-upstream-to "origin/$branch" || true
      [[ "$debug" == true ]] && echo "create_worktree_for_branch: worktree added from origin/$branch" >&2
    else
      # Fallback: remote declared it exists, but we still don't see it locally.
      # Start new branch from default (or HEAD if default isn't available).
      [[ "$debug" == true ]] && echo "create_worktree_for_branch: could not resolve origin/$branch, using fallback" >&2
      local defb base_ref
      defb="$(default_remote_branch "$base")"
      base_ref="origin/$defb"
      if ! remote_branch_exists "$base" "$defb"; then base_ref="HEAD"; fi
      echo "Could not resolve origin/$branch locally; creating from $base_ref instead"
      git -C "$base" worktree add -b "$branch" "$dest" "$base_ref" </dev/null
      CNT_WORKTREE_ADDED=$((CNT_WORKTREE_ADDED + 1))
      git -C "$dest" push -u origin HEAD:"$branch" || true
    fi
  else
    # New branch off default; cope with single-branch bases (no origin/<default>)
    echo "Branch not found: $branch (on remote, creating new)"
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: creating new branch from default" >&2
    local defb base_ref
    defb="$(default_remote_branch "$base")"
    base_ref="origin/$defb"
    if ! remote_branch_exists "$base" "$defb"; then
      # In single-branch clones, we may not have origin/<default>; fall back to HEAD.
      base_ref="HEAD"
    fi
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: base_ref='$base_ref'" >&2
    echo "Adding worktree $dest (new branch '$branch' from $base_ref)"
    git -C "$base" worktree add -b "$branch" "$dest" "$base_ref" </dev/null
    git -C "$dest" push -u origin HEAD:"$branch" || true
    CNT_WORKTREE_ADDED=$((CNT_WORKTREE_ADDED + 1))
    [[ "$debug" == true ]] && echo "create_worktree_for_branch: worktree added and pushed" >&2
  fi
  return 0
}

# --- Argument parsing --------------------------------------------------------
parse_args() {
  if [ ! -f "repos.list" ] && [ -f "repos-to-clone.list" ]; then
    REPOS_FILE="repos-to-clone.list"
  else
    REPOS_FILE="repos.list"
  fi

  DEBUG=false

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -f|--file) shift; [ "$#" -gt 0 ] && REPOS_FILE="$1" || { usage; exit 1; }; shift ;;
      -d|--debug) DEBUG=true; shift ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
    esac
  done

  [[ "$DEBUG" == true ]] && echo "Using repo list file: $REPOS_FILE" >&2

  if [ ! -f "$REPOS_FILE" ]; then
    echo "File '$REPOS_FILE' not found." >&2
    exit 1
  fi

  [[ "$DEBUG" == true ]] && echo "Argument parsing complete." >&2
  return 0
}

plan_forward() {
  local file="$1" parent_dir="$2" debug="$3"
  local line trimmed tok1 tok2 remote_spec remote_https repo ref target is_opt no_worktree
  local current_repo_https fallback_https
  
  # Initialize fallback to current repo
  current_repo_https="$(get_current_repo_remote_https)"
  fallback_https="$current_repo_https"
  
  [[ "$debug" == true ]] && echo "Planning from file: $file" >&2
  [[ "$debug" == true ]] && echo "Parent dir for clones: $parent_dir" >&2
  [[ "$debug" == true ]] && echo "Planning fallback starts as: $fallback_https" >&2
  
  while IFS= read -r line || [ -n "$line" ]; do
    # trim, strip comments
    [[ "$debug" == true ]] && echo "Planning line: $line" >&2
    trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in \#*|"") continue ;; esac
    case "$trimmed" in *" # "*) trimmed="${trimmed%% # *}" ;; *" #"*) trimmed="${trimmed%% #*}" ;; esac
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"; trimmed=${trimmed%$'\r'}
    [ -z "$trimmed" ] && continue

    set -- $trimmed
    tok1="$1"; shift || true

    case "$tok1" in
      @*)
        # Worktree line: count as reference to fallback repo
        # Check if --no-worktree flag is present
        no_worktree=0
        while [ "$#" -gt 0 ]; do
          case "$1" in
            -n|--no-worktree) no_worktree=1 ;;
          esac
          shift
        done
        
        # If it's a worktree (not --no-worktree), count it as a reference to fallback
        if [ "$no_worktree" -eq 0 ]; then
          [[ "$debug" == true ]] && echo "Planning: worktree on fallback $fallback_https" >&2
          plan_remember_remote "$fallback_https" 0 ""
        fi
        # Note: worktree lines don't change the fallback
        ;;
      *)
        # clone line: owner/repo[@ref] or https url
        remote_spec="$tok1"
        case "$remote_spec" in
          *@*) repo="${remote_spec%@*}"; ref="${remote_spec##*@}" ;;
          *)   repo="$remote_spec"; ref="" ;;
        esac
        remote_https="$(spec_to_https "$repo")"

        # detect optional explicit target dir (second token that isn't an option)
        target=""
        if [ "$#" -gt 0 ]; then
          tok2="$1"
          case "$tok2" in -*) is_opt=1 ;; *) is_opt=0 ;; esac
          [ "$is_opt" -eq 0 ] && target="$tok2"
        fi

        if [ -z "$ref" ]; then
          if [ -n "$target" ]; then
            plan_remember_remote "$remote_https" 1 "$target"
          else
            plan_remember_remote "$remote_https" 1 "${remote_https##*/}"
          fi
        else
          plan_remember_remote "$remote_https" 0 ""
        fi
        
        # Update fallback for subsequent lines
        fallback_https="$remote_https"
        [[ "$debug" == true ]] && echo "Planning: fallback updated to $fallback_https" >&2
        ;;
    esac
  done <"$file"
  [[ "$debug" == true ]] && echo "Planning complete." >&2
  return 0
}

# --- Main --------------------------------------------------------------------
main() {
  parse_args "$@"
  check_prerequisites "$DEBUG"
  
  # Skip authentication check if all remotes are local
  if has_non_local_remotes "$REPOS_FILE"; then
    check_non_interactive_auth "$DEBUG"
  else
    [[ "$DEBUG" == true ]] && echo "All remotes are local; skipping authentication check." >&2
  fi

  local start_dir parent_dir
  start_dir="$(pwd)"
  parent_dir="$(dirname "$start_dir")"

  plan_forward "$REPOS_FILE" "$parent_dir" "$DEBUG"

  # Fallback repo initialised to the CURRENT repo's remote
  local current_repo_https fallback_repo_https
  current_repo_https="$(get_current_repo_remote_https)"
  fallback_repo_https="$current_repo_https"
  local fallback_repo_local
  fallback_repo_local="$start_dir"
  [[ "$DEBUG" == true ]] && echo "Initial fallback repo: $fallback_repo_https → $fallback_repo_local" >&2


  while IFS= read -r line || [ -n "$line" ]; do
    # Trim & ignore comments/blank
    [[ "$DEBUG" == true ]] && echo "Processing line: $line" >&2
    local trimmed="${line#"${line%%[![:space:]]*}"}"
    case "$trimmed" in \#*|"") continue ;; esac
    case "$trimmed" in *" # "*) trimmed="${trimmed%% # *}" ;; *" #"*) trimmed="${trimmed%% #*}" ;; esac
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"; trimmed=${trimmed%$'\r'}
    # if the lie is now empty
    if [ -z "$trimmed" ]; then
      [[ "$DEBUG" == true ]] && echo "Skipping empty line after trimming." >&2
      continue
    fi

    CURRENT_LINE="$trimmed"
    [[ "$DEBUG" == true ]] && echo "Current line to process: $CURRENT_LINE" >&2
    trace "$CURRENT_LINE"

    local line_rc=0
    set +e
    {
      [[ "$DEBUG" == true ]] && echo "Parsing line: $trimmed" >&2
      local rc=0
      # Parse with current fallback
      local parsed repo_spec target_dir all_branches is_worktree
      parsed="$(parse_effective_line "$trimmed" "$fallback_repo_https")"
      IFS=$'\x1f' read -r repo_spec target_dir all_branches is_worktree <<<"$parsed"
      [ -z "$repo_spec" ] && { rc=0; ( exit "$rc" ); }

      if [ "$is_worktree" -eq 1 ]; then
        local branch=""; case "$repo_spec" in *@*) branch="${repo_spec##*@}" ;; esac
        local base_abs
        if [ "$fallback_repo_https" = "$current_repo_https" ]; then
          base_abs="$start_dir"
        else
          # Check if this remote was already cloned (possibly with a custom directory)
          local idx; idx="$(remote_index "$fallback_repo_https")"
          if [ "$idx" -ge 0 ] && [ -n "${REMOTE_LOCAL_PATH[$idx]}" ]; then
            # Use the actual path where it was cloned
            base_abs="${REMOTE_LOCAL_PATH[$idx]}"
            [[ "$DEBUG" == true ]] && echo "Using existing clone at '$base_abs' for worktree base" >&2
          else
            # Not cloned yet, use planned base name
            local base_name; base_name="$(plan_base_name "$fallback_repo_https")"
            base_abs="$parent_dir/$base_name"
            ensure_base_exists "$fallback_repo_https" "$base_abs" "$DEBUG" || rc=$?
          fi
        fi
        [ $rc -eq 0 ] && create_worktree_for_branch "$base_abs" "$branch" "$target_dir" "$parent_dir" "$DEBUG" || rc=$?
        fallback_repo_local="$base_abs"
        remember_remote "$fallback_repo_https" "$fallback_repo_local"
      else
        local repo_no_ref ref is_branch_clone this_remote_https
        case "$repo_spec" in
          *@*) repo_no_ref="${repo_spec%@*}"; ref="${repo_spec##*@}"; is_branch_clone=1 ;;
          *)   repo_no_ref="$repo_spec";      ref="";                 is_branch_clone=0 ;;
        esac
        this_remote_https="$(spec_to_https "$repo_no_ref")"
        local seen_before; [ "$(remote_index "$this_remote_https")" -ge 0 ] && seen_before=1 || seen_before=0

        clone_one_repo "$repo_spec" "$target_dir" "$parent_dir" "$all_branches" "$DEBUG" || rc=$?
        fallback_repo_https="$this_remote_https"

        if [ "$is_branch_clone" -eq 0 ]; then
          fallback_repo_local="$CLONE_DEST"
          remember_remote "$this_remote_https" "$fallback_repo_local"
        else
          if [ "$seen_before" -eq 0 ] && [ "$(plan_has_full "$this_remote_https")" -eq 1 ]; then
            local base_name; base_name="$(plan_base_name "$this_remote_https")"
            local base_abs="$parent_dir/$base_name"
            ensure_base_exists "$this_remote_https" "$base_abs" "$DEBUG" || rc=$?
            fallback_repo_local="$base_abs"
            remember_remote "$this_remote_https" "$fallback_repo_local"
          elif [ "$seen_before" -eq 0 ]; then
            fallback_repo_local="$CLONE_DEST"
            remember_remote "$this_remote_https" "$fallback_repo_local"
          else
            # Repo was seen before: update fallback_repo_local to the actual clone destination
            fallback_repo_local="$CLONE_DEST"
            remember_remote "$this_remote_https" "$fallback_repo_local"
          fi
        fi
      fi
      ( exit "$rc" )
    }
    line_rc=$?
    # Note: Debug statement must be after line_rc=$? to avoid capturing debug statement's exit code
    [[ "$DEBUG" == true ]] && echo "Finished processing line: $CURRENT_LINE" >&2
    set -e

    [[ "$DEBUG" == true ]] && echo "Line result code: $line_rc" >&2
    [[ $DEBUG == true ]] && echo "Updating counters." >&2
    CNT_TOTAL=$((CNT_TOTAL + 1))
    [[ "$DEBUG" == true ]] && echo "CNT_TOTAL=$CNT_TOTAL" >&2
    
    [[ "$DEBUG" = "true" ]] && echo "Providing feedback" >&2
    case "$line_rc" in
      0) : ;;
      2) printf '↷ skipped: %s\n' "$CURRENT_LINE" >&2 ;;
      *) printf '✖ line failed (rc=%s): %s\n' "$line_rc" "$CURRENT_LINE" >&2; CNT_ERRORS=$((CNT_ERRORS + 1)) ;;
    esac
    [[ "$DEBUG" == true ]] && echo "Moving to next line." >&2
  done <"$REPOS_FILE"

  echo
  echo "Summary:"
  echo "  Instructions processed : $CNT_TOTAL"
  echo "  Skipped (already present): $CNT_SKIPPED"
  echo "  Cloned (full)           : $CNT_CLONED_FULL"
  echo "  Cloned (single-branch)  : $CNT_CLONED_BRANCH"
  echo "  Worktrees added         : $CNT_WORKTREE_ADDED"
  echo "  Errors                  : $CNT_ERRORS"
}

main "$@"
