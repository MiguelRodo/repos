#!/usr/bin/env bash
# create-repos.sh — create GitHub repos (with branches) from a list
# Requires: bash 3.2+, curl, jq, mktemp

set -o errexit   # same as -e
set -o nounset   # same as -u
set -o pipefail

# Never prompt for credentials (prevents stdin reads that can kill the loop)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

git() { command git "$@" </dev/null; }

# — Prerequisites —
for cmd in curl git jq mktemp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf "Error: '%s' is required but not found in PATH.\n" "$cmd" >&2
    exit 1
  fi
done

# — Debug support —
DEBUG=false
DEBUG_FILE=""
DEBUG_FD=3  # Use FD 3 for debug output (compatible with Bash 3.2+)

debug() {
  if $DEBUG; then
    printf "[DEBUG create-repos.sh] %s\n" "$*" >&$DEBUG_FD
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

# URL encode a string using jq
urlencode() {
  printf '%s' "$1" | jq -rR '@uri'
}

# ── CONFIG & USAGE ─────────────────────────────────────────────────────────────
if [ ! -f "repos.list" ] && [ -f "repos-to-clone.list" ]; then
  REPOS_FILE="repos-to-clone.list"
else
  REPOS_FILE="repos.list"
fi

usage() {
  cat <<EOF
Usage: $0 [-f <repo-list>] [-p|--public] [--debug] [--debug-file [file]]

  -f FILE              read lines from FILE (default: repos.list)
  -p, --public         create repos as public (default: private)
  --debug              enable debug output to stderr
  --debug-file [file]  enable debug output to file (auto-generated if not specified)
  -h, --help           show this message and exit

Each non-blank, non-# line of <repo-list> can be:
  owner/repo[@branch] [target_directory]
    Creates/checks the repo and optionally checks the branch exists.
  @branch [target_directory]
    Checks if the branch exists on the "fallback repo" (the most recently
    processed owner/repo line). If not in a git repo, fallback starts empty.

Target directories are informational only (used by clone-repos.sh).
EOF
  exit "${1:-1}"
}

PRIVATE_FLAG=true
CLI_PUBLIC_FLAG_SET=false
while [ $# -gt 0 ]; do
  case $1 in
    -f)           shift; REPOS_FILE="$1"; shift ;;
    -p|--public)  PRIVATE_FLAG=false; CLI_PUBLIC_FLAG_SET=true; shift ;;
    --debug)      DEBUG=true; shift ;;
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
        DEBUG_FILE=$(mktemp "${TEMP_DIR}/repos-create-debug-XXXXXX")
      fi
      ;;
    -h|--help)    usage 0 ;;
    *)            printf "Unknown argument: %s\n" "$1" >&2; usage ;;
  esac
done

# Set up debug file descriptor if needed
if [ -n "$DEBUG_FILE" ]; then
  exec 3>>"$DEBUG_FILE"
  printf "create-repos.sh debug output will be appended to: %s\n" "$DEBUG_FILE" >&2
else
  # Redirect FD 3 to stderr by default
  exec 3>&2
fi

debug "=== create-repos.sh Debug Session Started ==="
debug "Repos file: $REPOS_FILE"
debug "Private flag (from CLI): $PRIVATE_FLAG"

[ -f "$REPOS_FILE" ] || { printf "Error: '%s' not found.\n" "$REPOS_FILE" >&2; exit 1; }

# Parse global --public / --private flags from repos.list.
# CLI flag (-p / --public) takes precedence; repos.list is only consulted when
# the user has not already provided a visibility flag on the command line.
# This mirrors the behaviour that setup-repos.sh used to provide.
if [ "$CLI_PUBLIC_FLAG_SET" = "false" ]; then
  while IFS= read -r _line || [ -n "$_line" ]; do
    _trimmed="${_line#"${_line%%[![:space:]]*}"}"
    case "$_trimmed" in \#*|"") continue ;; esac
    case "$_trimmed" in *" # "*) _trimmed="${_trimmed%% # *}" ;; *" #"*) _trimmed="${_trimmed%% #*}" ;; esac
    _trimmed="${_trimmed%"${_trimmed##*[![:space:]]}"}"; _trimmed="${_trimmed%$'\r'}"
    [ -z "$_trimmed" ] && continue
    case "$_trimmed" in
      --public|--public[[:space:]]*)
        PRIVATE_FLAG=false
        debug "Enabled --public from repos.list"
        ;;
      --private|--private[[:space:]]*)
        PRIVATE_FLAG=true
        debug "Enabled --private from repos.list"
        ;;
    esac
  done < "$REPOS_FILE"
fi

debug "Private flag (effective): $PRIVATE_FLAG"

# ── CREDENTIALS WITH FALLBACK (will be retrieved only if needed) ────────────────
# Returns 0 if credentials are available, 1 if not
get_credentials() {
  debug "Attempting to get GitHub credentials..."
  # Sanitize environment variables to prevent header/credential injection
  [ -n "${GH_USER:-}" ] && GH_USER=$(printf '%s\n' "$GH_USER" | tr -d '\r\n')
  [ -n "${GH_TOKEN:-}" ] && GH_TOKEN=$(printf '%s\n' "$GH_TOKEN" | tr -d '\r\n')

  if [ -z "${GH_TOKEN-}" ] || [ -z "${GH_USER-}" ]; then
    debug "GH_TOKEN or GH_USER not set, trying git credential fill..."
    # Try to get credentials, but don't fail if unavailable
    if ! creds=$(
      printf 'url=https://github.com\n\n' \
        | git -c credential.interactive=false credential fill 2>/dev/null
    ); then
      debug "git credential fill failed"
      printf "Warning: GitHub credentials not available. Skipping repository creation/verification.\n" >&2
      return 1
    fi
    # Parse credentials with sed instead of awk -F= to support tokens with equals signs.
    # Sanitize retrieved values with tr to prevent header injection.
    [ -z "${GH_USER-}" ] && \
      GH_USER=$(printf '%s\n' "$creds" | sed -n 's/^username=//p' | tr -d '\r\n')
    [ -z "${GH_TOKEN-}" ] && \
      GH_TOKEN=$(printf '%s\n' "$creds" | sed -n 's/^password=//p' | tr -d '\r\n')
    
    debug "Retrieved GH_USER: ${GH_USER:+<present>}"
    debug "Retrieved GH_TOKEN: ${GH_TOKEN:+<present>}"
    
    # Check if we actually got credentials
    if [ -z "${GH_USER-}" ] || [ -z "${GH_TOKEN-}" ]; then
      debug "Credentials incomplete after retrieval"
      printf "Warning: GitHub credentials not available. Skipping repository creation/verification.\n" >&2
      return 1
    fi
  else
    debug "Using existing GH_TOKEN and GH_USER from environment"
    debug "Environment GH_USER: ${GH_USER:+<present>}"
    debug "Environment GH_TOKEN: ${GH_TOKEN:+<present>}"
  fi

  debug "Credentials successfully obtained"
  return 0
}

API_URL="https://api.github.com"

# ── Token validation ───────────────────────────────────────────────────────────
# Validates that the provided token is valid by making a test API call
# Returns 0 if token is valid, 1 if invalid
validate_token() {
  local auth_header="$1"
  debug "Validating GitHub token..."
  
  # Make a simple API call to check token validity
  local response
  response=$(curl -s -H "$auth_header" -- "$API_URL/user")
  
  # Check if response is empty
  if [ -z "$response" ]; then
    debug "Token validation: Empty response from API"
    # If we can't validate, we should still try to proceed
    # This could be a network issue rather than an invalid token
    return 0
  fi
  
  # Check for errors using jq
  local message
  message=$(printf '%s\n' "$response" | jq -r '.message // empty')

  if [ "$message" = "Bad credentials" ]; then
    debug "Token validation failed: Bad credentials"
    printf "Error: Invalid GitHub token. Please check your credentials.\n" >&2
    printf "The provided token does not have valid GitHub API access.\n" >&2
    return 1
  fi
  
  if [ "$message" = "Requires authentication" ]; then
    debug "Token validation failed: Requires authentication"
    printf "Error: GitHub authentication required. Please check your credentials.\n" >&2
    return 1
  fi
  
  # If we can extract a login field, the token is valid
  if printf '%s\n' "$response" | jq -e '.login' >/dev/null 2>&1; then
    debug "Token validation successful"
    return 0
  fi
  
  # If there's any other message, report it
  if [ -n "$message" ]; then
    debug "Token validation failed: $message"
    printf "Error: GitHub API error: %s\n" "$message" >&2
    return 1
  fi
  
  # If we get here, assume valid (we got a response without error)
  debug "Token appears valid (no error detected)"
  return 0
}

# ── Helpers for branch creation ────────────────────────────────────────────────
api_get_field() {
  local url="$1"; local field="$2"
  # Use getpath with split to support nested fields (e.g. "commit.sha") securely
  curl -s -H "$AUTH_HDR" -- "$url" | jq -r --arg field "$field" 'getpath($field | split("."))'
}

create_branch() {
  local owner="$1"; local repo="$2"; local newbr="$3"
  local e_owner e_repo e_defbr
  e_owner=$(urlencode "$owner")
  e_repo=$(urlencode "$repo")

  local defbr
  defbr=$( api_get_field "$API_URL/repos/$e_owner/$e_repo" "default_branch" )
  e_defbr=$(urlencode "$defbr")

  local defsha
  defsha=$(
    curl -s -H "$AUTH_HDR" -- \
      "$API_URL/repos/$e_owner/$e_repo/git/ref/heads/$e_defbr" \
    | jq -r '.object.sha // .sha'
  )

  local payload
  payload=$(jq -n --arg ref "refs/heads/$newbr" --arg sha "$defsha" '{ref: $ref, sha: $sha}')

  curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d "$payload" -- \
    "$API_URL/repos/$e_owner/$e_repo/git/refs"
}

# ── Get current repo info (for initial fallback) ───────────────────────────────
get_current_repo_info() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Get origin URL
    local origin_url
    origin_url=$(git config --get -- remote.origin.url 2>/dev/null || echo "")
    
    if [ -z "$origin_url" ]; then
      return 1
    fi
    
    # Convert to HTTPS format and extract owner/repo
    case "$origin_url" in
      https://github.com/*)
        origin_url=${origin_url#https://github.com/}
        ;;
      git@github.com:*)
        origin_url=${origin_url#git@github.com:}
        ;;
      ssh://git@github.com/*)
        origin_url=${origin_url#ssh://git@github.com/}
        ;;
      *)
        return 1
        ;;
    esac
    
    # Remove .git suffix
    origin_url=${origin_url%.git}

    # Validate for path traversal
    case "$origin_url" in
      *..*)
        return 1
        ;;
    esac
    
    # Extract owner and repo
    local owner repo
    owner=${origin_url%%/*}
    repo=${origin_url#*/}

    # Validate owner and repo names
    # - Must only contain alphanumeric characters, hyphens, underscores, or dots
    # - Must not start with a hyphen (prevents argument injection)
    local VALID_PATTERN="^[a-zA-Z0-9._][a-zA-Z0-9._-]*$"
    if [[ ! "$owner" =~ $VALID_PATTERN ]] || [[ ! "$repo" =~ $VALID_PATTERN ]]; then
      return 1
    fi
    
    # Set global fallback variables
    fallback_owner="$owner"
    fallback_repo="$repo"
    return 0
  fi
  return 1
}

# ── MAIN LOOP ─────────────────────────────────────────────────────────────────
# Track fallback repo for @branch lines (similar to clone-repos.sh)
fallback_owner=""
fallback_repo=""

# Initialize fallback to current repo (if we're in a git repo)
debug "Checking if in a git repo for fallback..."
if get_current_repo_info; then
  debug "Initial fallback repo set to: $fallback_owner/$fallback_repo"
else
  debug "Not in a git repo or no origin remote found"
fi

debug "Starting to process repos.list..."
line_num=0

while IFS= read -r line || [ -n "$line" ]; do
  line_num=$((line_num + 1))
  case "$line" in ''|\#*) debug "Line $line_num: Skipping empty or comment line"; continue ;; esac
  
  debug "Line $line_num: Processing: $line"

  # Parse line to extract repo_spec and any flags
  # Check if line is just a global flag (--codespaces, --public, --private, --worktree)
  trimmed_line="${line#"${line%%[![:space:]]*}"}"
  trimmed_line="${trimmed_line%"${trimmed_line##*[![:space:]]}"}"; trimmed_line=${trimmed_line%$'\r'}
  
  # Skip lines that are just global flags (already applied before this loop)
  case "$trimmed_line" in
    --codespaces|--codespaces[[:space:]]*|\
    --public|--public[[:space:]]*|\
    --private|--private[[:space:]]*|\
    --worktree|--worktree[[:space:]]*)
      debug "Line $line_num: Skipping global flag line: $trimmed_line"
      continue
      ;;
  esac

  repo_spec=${trimmed_line%%[[:space:]]*}
  
  # Parse line-specific flags for this repo
  line_is_public=""
  rest_of_line="${line#*[[:space:]]}"
  if [ "$rest_of_line" != "$line" ]; then
    # There are additional tokens on the line
    case " $rest_of_line " in
      *" --public "*)
        line_is_public=true
        debug "Line $line_num: Found --public flag on this line"
        ;;
      *" --private "*)
        line_is_public=false
        debug "Line $line_num: Found --private flag on this line"
        ;;
    esac
  fi
  
  # Handle @branch lines (worktrees) - check branch on fallback repo
  case "$repo_spec" in
    @*)
      branch=${repo_spec#@}
      # Extract branch name, removing any options like --no-worktree
      branch=${branch%%[[:space:]]*}
      if [ -z "$branch" ] || [[ "$branch" == -* ]] || ! git check-ref-format --allow-onelevel "$branch"; then
        printf "Error: '%s' is not a valid Git branch name.\n" "$branch" >&2
        continue
      fi
      debug "Line $line_num: @branch detected: $branch"
      
      if [ -z "$fallback_owner" ] || [ -z "$fallback_repo" ]; then
        debug "Line $line_num: No fallback repo available for @$branch"
        printf "Warning: @%s cannot be processed - no previous owner/repo line found to use as fallback repository; skipping branch check.\n" "$branch"
        continue
      fi
      
      debug "Line $line_num: Will check/create branch $branch on fallback repo $fallback_owner/$fallback_repo"
      
      # Get credentials if needed
      if ! get_credentials; then
        debug "Line $line_num: No credentials available, skipping branch check"
        printf "Skipping branch check for @%s (no credentials)\n" "$branch"
        continue
      fi
      AUTH_HDR="Authorization: token $GH_TOKEN"
      
      # Validate token
      if ! validate_token "$AUTH_HDR"; then
        debug "Line $line_num: Token validation failed, skipping branch check"
        printf "Skipping branch check for @%s on %s/%s (invalid credentials)\n" "$branch" "$fallback_owner" "$fallback_repo" >&2
        continue
      fi
      
      # Check if branch exists on fallback repo
      debug "Line $line_num: Checking if branch $branch exists on $fallback_owner/$fallback_repo"
      ref_status=$(
        curl -s -o /dev/null -w "%{http_code}" \
          -H "$AUTH_HDR" -- \
          "$API_URL/repos/$(urlencode "$fallback_owner")/$(urlencode "$fallback_repo")/git/refs/heads/$(urlencode "$branch")"
      )
      debug "Line $line_num: Branch check returned HTTP $ref_status"
      if [ "$ref_status" -eq 200 ]; then
        printf "Branch exists: %s\n" "$branch"
      elif [ "$ref_status" -eq 404 ]; then
        printf "Creating branch %s on %s/%s ... " "$branch" "$fallback_owner" "$fallback_repo"
        debug "Line $line_num: Creating branch $branch"
        code=$( create_branch "$fallback_owner" "$fallback_repo" "$branch" )
        debug "Line $line_num: Branch creation returned HTTP $code"
        if [ "$code" -eq 201 ]; then
          printf "done.\n"
        else
          printf "failed (HTTP %s).\n" "$code"
        fi
      else
        printf "Error checking branch %s on %s/%s (HTTP %s).\n" "$branch" "$fallback_owner" "$fallback_repo" "$ref_status"
      fi
      
      # @branch lines don't change the fallback
      debug "Line $line_num: @branch processing complete, fallback remains: $fallback_owner/$fallback_repo"
      continue
      ;;
  esac
  
  # Skip local remotes (file:// URLs and absolute paths, including Windows)
  case "$repo_spec" in
    file://*|[a-zA-Z]:/*|[a-zA-Z]:\\*|/*|\\*)
      debug "Line $line_num: Skipping local remote: $repo_spec"
      printf "Skipping local remote: %s\n" "$repo_spec"
      continue
      ;;
  esac
  
  # Skip non-GitHub HTTPS/SSH URLs
  case "$repo_spec" in
    https://github.com/*|git@github.com:*|ssh://git@github.com/*)
      # This is a GitHub URL, process it
      debug "Line $line_num: Detected GitHub URL: $repo_spec"
      ;;
    https://*|git@*|ssh://*)
      # This is a non-GitHub remote URL
      debug "Line $line_num: Skipping non-GitHub remote: $repo_spec"
      printf "Skipping non-GitHub remote: %s\n" "$repo_spec"
      continue
      ;;
  esac
  
  repo_path=${repo_spec%@*}
  # Validate repo_path format (must be owner/repo)
  if [[ ! "$repo_path" =~ ^[^/]+/[^/]+$ ]]; then
    printf "Error: repository spec must be in 'owner/repo' format: %s\n" "$repo_spec" >&2
    exit 1
  fi

  # Validate repo_path to prevent path traversal
  case "$repo_path" in
    *..*) 
      printf "Error: repository spec contains '..': %s\n" "$repo_spec" >&2
      exit 1
      ;;
  esac

  owner=${repo_path%%/*}
  repo=${repo_path##*/}

  # Validate owner and repo names
  # - Must not start with a hyphen (prevents argument injection)
  # - Must only contain alphanumeric characters, hyphens, underscores, or dots
  # - Following GitHub conventions (mostly)
  VALID_PATTERN="^[a-zA-Z0-9][a-zA-Z0-9._-]*$"
  if [[ ! "$owner" =~ $VALID_PATTERN ]]; then
    printf "Error: invalid owner name: %s\n" "$owner" >&2
    exit 1
  fi
  if [[ ! "$repo" =~ $VALID_PATTERN ]]; then
    printf "Error: invalid repository name: %s\n" "$repo" >&2
    exit 1
  fi
  case "$repo_spec" in *@*) branch=${repo_spec##*@} ;; *) branch="" ;; esac
  
  if [ -n "$branch" ] && ( [[ "$branch" == -* ]] || ! git check-ref-format --allow-onelevel "$branch" ); then
    printf "Error: '%s' is not a valid Git branch name.\n" "$branch" >&2
    # Still update fallback repo for subsequent @branch lines
    fallback_owner="$owner"
    fallback_repo="$repo"
    continue
  fi

  debug "Line $line_num: Parsed - owner: $owner, repo: $repo, branch: ${branch:-<none>}"

  # Get credentials only when we need them (for GitHub repos)
  if ! get_credentials; then
    debug "Line $line_num: No credentials, skipping repo $repo_spec"
    printf "Skipping repository creation/verification for %s (no credentials)\n" "$repo_spec"
    # Still update fallback repo for subsequent @branch lines
    fallback_owner="$owner"
    fallback_repo="$repo"
    debug "Line $line_num: Updated fallback to: $fallback_owner/$fallback_repo"
    continue
  fi
  AUTH_HDR="Authorization: token $GH_TOKEN"

  # Validate token before making API calls
  if ! validate_token "$AUTH_HDR"; then
    debug "Line $line_num: Token validation failed, skipping repo $repo_spec"
    printf "Skipping repository creation/verification for %s (invalid credentials)\n" "$repo_spec" >&2
    # Still update fallback repo for subsequent @branch lines
    fallback_owner="$owner"
    fallback_repo="$repo"
    debug "Line $line_num: Updated fallback to: $fallback_owner/$fallback_repo"
    continue
  fi

  # 1) Determine owner type (User vs Organization)
  debug "Line $line_num: Checking owner type for $owner"
  owner_info=$(curl -s -H "$AUTH_HDR" -- "$API_URL/users/$(urlencode "$owner")")
  owner_type=$(printf '%s\n' "$owner_info" | jq -r '.type // empty')
  
  debug "Line $line_num: Owner type: $owner_type"

  case "$owner_type" in
    Organization)
      create_url="$API_URL/orgs/$(urlencode "$owner")/repos"
      ;;
    User)
      create_url="$API_URL/user/repos"
      ;;
    *)
      printf "Error: could not determine owner type for '%s'.\n" "$owner"
      continue
      ;;
  esac

  # 2) Check repo existence
  status=$(
    curl -s -o /dev/null -w "%{http_code}" \
      -H "$AUTH_HDR" -- \
      "$API_URL/repos/$(urlencode "$owner")/$(urlencode "$repo")"
  )
  if [ "$status" -eq 200 ]; then
    printf "Exists: %s/%s\n" "$owner" "$repo"
  elif [ "$status" -eq 404 ]; then
    # build payload (auto_init if we’ll push a branch later)
    # Determine if this repo should be private or public
    # Line-specific flag takes precedence over global flag
    this_repo_private=""
    if [ -n "$line_is_public" ]; then
      # Line has explicit --public or --private flag
      if [ "$line_is_public" = "true" ]; then
        this_repo_private=false
        debug "Line $line_num: Using line-specific --public flag"
      else
        this_repo_private=true
        debug "Line $line_num: Using line-specific --private flag"
      fi
    else
      # Use global default
      this_repo_private=$PRIVATE_FLAG
      debug "Line $line_num: Using global private flag: $this_repo_private"
    fi
    
    # Build JSON payload safely using jq
    if [ -n "$branch" ]; then
      payload=$(jq -n --arg name "$repo" --argjson private "$this_repo_private" '{name: $name, private: $private, auto_init: true}')
    else
      payload=$(jq -n --arg name "$repo" --argjson private "$this_repo_private" '{name: $name, private: $private}')
    fi

    printf "Creating repo %s/%s ... " "$owner" "$repo"
    http_code=$(
      curl -s -o /dev/null -w "%{http_code}" \
        -H "$AUTH_HDR" \
        -H "Content-Type: application/json" \
        -d "$payload" -- \
        "$create_url"
    )
    if [ "$http_code" -eq 201 ]; then
      printf "done.\n"
    else
      printf "failed (HTTP %s).\n" "$http_code"
      continue
    fi
  else
    printf "Error checking %s/%s (HTTP %s).\n" "$owner" "$repo" "$status"
    continue
  fi

  # 3) Ensure branch exists
  if [ -n "$branch" ]; then
    ref_status=$(
      curl -s -o /dev/null -w "%{http_code}" \
        -H "$AUTH_HDR" -- \
        "$API_URL/repos/$(urlencode "$owner")/$(urlencode "$repo")/git/refs/heads/$(urlencode "$branch")"
    )
    if [ "$ref_status" -eq 200 ]; then
      printf "Branch exists: %s\n" "$branch"
    elif [ "$ref_status" -eq 404 ]; then
      printf "Creating branch %s ... " "$branch"
      code=$( create_branch "$owner" "$repo" "$branch" )
      if [ "$code" -eq 201 ]; then
        printf "done.\n"
      else
        printf "failed (HTTP %s).\n" "$code"
      fi
    else
      printf "Error checking branch %s (HTTP %s).\n" "$branch" "$ref_status"
    fi
  fi
  
  # Update fallback repo for subsequent @branch lines
  fallback_owner="$owner"
  fallback_repo="$repo"

done < "$REPOS_FILE"

debug "=== create-repos.sh Debug Session Ended ==="

# Close debug file descriptor if opened
if [ -n "$DEBUG_FILE" ]; then
  exec 3>&-
fi
