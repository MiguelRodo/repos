#!/usr/bin/env bash
# create-repos.sh — create GitHub repos (with branches) from a list
# Requires: bash 3.2+, curl

set -o errexit   # same as -e
set -o nounset   # same as -u
set -o pipefail

# — Debug support —
DEBUG=false
DEBUG_FILE=""
DEBUG_FD=3  # Use FD 3 for debug output (compatible with Bash 3.2+)

debug() {
  if $DEBUG; then
    echo "[DEBUG create-repos.sh] $*" >&$DEBUG_FD
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
while [ $# -gt 0 ]; do
  case $1 in
    -f)           shift; REPOS_FILE="$1"; shift ;;
    -p|--public)  PRIVATE_FLAG=false; shift ;;
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
    *)            echo "Unknown argument: $1" >&2; usage ;;
  esac
done

# Set up debug file descriptor if needed
if [ -n "$DEBUG_FILE" ]; then
  exec 3>>"$DEBUG_FILE"
  echo "create-repos.sh debug output will be appended to: $DEBUG_FILE" >&2
else
  # Redirect FD 3 to stderr by default
  exec 3>&2
fi

debug "=== create-repos.sh Debug Session Started ==="
debug "Repos file: $REPOS_FILE"
debug "Private flag: $PRIVATE_FLAG"

[ -f "$REPOS_FILE" ] || { echo "Error: '$REPOS_FILE' not found." >&2; exit 1; }

# ── CREDENTIALS WITH FALLBACK (will be retrieved only if needed) ────────────────
# Returns 0 if credentials are available, 1 if not
get_credentials() {
  debug "Attempting to get GitHub credentials..."
  if [ -z "${GH_TOKEN-}" ] || [ -z "${GH_USER-}" ]; then
    debug "GH_TOKEN or GH_USER not set, trying git credential fill..."
    # Try to get credentials, but don't fail if unavailable
    if ! creds=$(
      printf 'url=https://github.com\n\n' \
        | git -c credential.interactive=false credential fill 2>/dev/null
    ); then
      debug "git credential fill failed"
      echo "Warning: GitHub credentials not available. Skipping repository creation/verification." >&2
      return 1
    fi
    [ -z "${GH_USER-}" ] && \
      GH_USER=$(printf '%s\n' "$creds" | tr -d '\r' | awk -F= '/^username=/ {print $2}')
    [ -z "${GH_TOKEN-}" ] && \
      GH_TOKEN=$(printf '%s\n' "$creds" | tr -d '\r' | awk -F= '/^password=/ {print $2}')
    
    debug "Retrieved GH_USER: ${GH_USER:+<present>}"
    debug "Retrieved GH_TOKEN: ${GH_TOKEN:+<present>}"
    
    # Check if we actually got credentials
    if [ -z "${GH_USER-}" ] || [ -z "${GH_TOKEN-}" ]; then
      debug "Credentials incomplete after retrieval"
      echo "Warning: GitHub credentials not available. Skipping repository creation/verification." >&2
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
if $PRIVATE_FLAG; then JSON_PRIVATE=true; else JSON_PRIVATE=false; fi

# ── Token validation ───────────────────────────────────────────────────────────
# Validates that the provided token is valid by making a test API call
# Returns 0 if token is valid, 1 if invalid
validate_token() {
  local auth_header="$1"
  debug "Validating GitHub token..."
  
  # Make a simple API call to check token validity
  local response
  response=$(curl -s -H "$auth_header" "$API_URL/user")
  
  # Check if response is empty or doesn't look like JSON
  if [ -z "$response" ]; then
    debug "Token validation: Empty response from API"
    # If we can't validate, we should still try to proceed
    # This could be a network issue rather than an invalid token
    return 0
  fi
  
  # Check if response contains an error message for bad credentials
  if printf '%s\n' "$response" | grep -q '"message".*"Bad credentials"'; then
    debug "Token validation failed: Bad credentials"
    echo "Error: Invalid GitHub token. Please check your credentials." >&2
    echo "The provided token does not have valid GitHub API access." >&2
    return 1
  fi
  
  # Check if response contains an error message for other auth issues
  if printf '%s\n' "$response" | grep -q '"message".*"Requires authentication"'; then
    debug "Token validation failed: Requires authentication"
    echo "Error: GitHub authentication required. Please check your credentials." >&2
    return 1
  fi
  
  # If we can extract a login field, the token is valid
  if printf '%s\n' "$response" | grep -q '"login"'; then
    debug "Token validation successful"
    return 0
  fi
  
  # If we get here and there's any message field with error-like content
  if printf '%s\n' "$response" | grep -q '"message"'; then
    local message
    # Note: This sed pattern doesn't handle escaped quotes within JSON values
    # If the pattern doesn't match, the message variable will contain the full grep line
    # For more robust JSON parsing, consider using jq if available
    message=$(printf '%s\n' "$response" | grep '"message"' | head -n1 | sed -E 's/.*"message": *"([^"]+)".*/\1/')
    # Validate that sed substitution succeeded by checking if message contains quotes
    # If it still contains JSON structure, use a generic message
    if printf '%s\n' "$message" | grep -q '"'; then
      debug "Token validation failed: Could not parse API error message"
      echo "Error: GitHub API authentication failed. Please check your credentials." >&2
    else
      debug "Token validation failed: $message"
      echo "Error: GitHub API error: $message" >&2
    fi
    return 1
  fi
  
  # If we get here, assume valid (we got a response without error)
  debug "Token appears valid (no error detected)"
  return 0
}

# ── Helpers for branch creation ────────────────────────────────────────────────
api_get_field() {
  url=$1; field=$2
  curl -s -H "$AUTH_HDR" "$url" \
    | grep "\"$field\"" \
    | head -n1 \
    | sed -E "s/.*\"$field\": *\"([^\"]+)\".*/\1/"
}

create_branch() {
  owner=$1; repo=$2; newbr=$3
  defbr=$( api_get_field "$API_URL/repos/$owner/$repo" default_branch )
  defsha=$(
    curl -s -H "$AUTH_HDR" \
      "$API_URL/repos/$owner/$repo/git/ref/heads/$defbr" \
    | grep '"sha"' | head -n1 \
    | sed -E 's/.*"sha": *"([^"]+)".*/\1/'
  )
  curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "$AUTH_HDR" -H "Content-Type: application/json" \
    -d "{\"ref\":\"refs/heads/$newbr\",\"sha\":\"$defsha\"}" \
    "$API_URL/repos/$owner/$repo/git/refs"
}

# ── Get current repo info (for initial fallback) ───────────────────────────────
get_current_repo_info() {
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Get origin URL
    local origin_url
    origin_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
    
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
    
    # Extract owner and repo
    local owner repo
    owner=${origin_url%%/*}
    repo=${origin_url#*/}
    
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
  
  # Skip lines that are just global flags
  case "$trimmed_line" in
    --codespaces|--codespaces[[:space:]]*|\
    --public|--public[[:space:]]*|\
    --private|--private[[:space:]]*|\
    --worktree|--worktree[[:space:]]*)
      debug "Line $line_num: Skipping global flag line: $trimmed_line"
      continue
      ;;
  esac

  repo_spec=${line%%[[:space:]]*}
  
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
      debug "Line $line_num: @branch detected: $branch"
      
      if [ -z "$fallback_owner" ] || [ -z "$fallback_repo" ]; then
        debug "Line $line_num: No fallback repo available for @$branch"
        echo "Warning: @$branch cannot be processed - no previous owner/repo line found to use as fallback repository; skipping branch check."
        continue
      fi
      
      debug "Line $line_num: Will check/create branch $branch on fallback repo $fallback_owner/$fallback_repo"
      
      # Get credentials if needed
      if ! get_credentials; then
        debug "Line $line_num: No credentials available, skipping branch check"
        echo "Skipping branch check for @$branch (no credentials)"
        continue
      fi
      AUTH_HDR="Authorization: token $GH_TOKEN"
      
      # Validate token
      if ! validate_token "$AUTH_HDR"; then
        debug "Line $line_num: Token validation failed, skipping branch check"
        echo "Skipping branch check for @$branch on $fallback_owner/$fallback_repo (invalid credentials)" >&2
        continue
      fi
      
      # Check if branch exists on fallback repo
      debug "Line $line_num: Checking if branch $branch exists on $fallback_owner/$fallback_repo"
      ref_status=$(
        curl -s -o /dev/null -w "%{http_code}" \
          -H "$AUTH_HDR" \
          "$API_URL/repos/$fallback_owner/$fallback_repo/git/refs/heads/$branch"
      )
      debug "Line $line_num: Branch check returned HTTP $ref_status"
      if [ "$ref_status" -eq 200 ]; then
        echo "Branch exists: $branch"
      elif [ "$ref_status" -eq 404 ]; then
        printf "Creating branch %s on %s/%s ... " "$branch" "$fallback_owner" "$fallback_repo"
        debug "Line $line_num: Creating branch $branch"
        code=$( create_branch "$fallback_owner" "$fallback_repo" "$branch" )
        debug "Line $line_num: Branch creation returned HTTP $code"
        if [ "$code" -eq 201 ]; then
          echo "done."
        else
          echo "failed (HTTP $code)."
        fi
      else
        echo "Error checking branch $branch on $fallback_owner/$fallback_repo (HTTP $ref_status)."
      fi
      
      # @branch lines don't change the fallback
      debug "Line $line_num: @branch processing complete, fallback remains: $fallback_owner/$fallback_repo"
      continue
      ;;
  esac
  
  # Skip local remotes (file:// URLs and absolute paths)
  case "$repo_spec" in
    file://*|/*)
      debug "Line $line_num: Skipping local remote: $repo_spec"
      echo "Skipping local remote: $repo_spec"
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
      echo "Skipping non-GitHub remote: $repo_spec"
      continue
      ;;
  esac
  
  repo_path=${repo_spec%@*}
  owner=${repo_path%%/*}
  repo=${repo_path##*/}
  case "$repo_spec" in *@*) branch=${repo_spec##*@} ;; *) branch="" ;; esac
  
  debug "Line $line_num: Parsed - owner: $owner, repo: $repo, branch: ${branch:-<none>}"

  # Get credentials only when we need them (for GitHub repos)
  if ! get_credentials; then
    debug "Line $line_num: No credentials, skipping repo $repo_spec"
    echo "Skipping repository creation/verification for $repo_spec (no credentials)"
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
    echo "Skipping repository creation/verification for $repo_spec (invalid credentials)" >&2
    # Still update fallback repo for subsequent @branch lines
    fallback_owner="$owner"
    fallback_repo="$repo"
    debug "Line $line_num: Updated fallback to: $fallback_owner/$fallback_repo"
    continue
  fi

  # 1) Determine owner type (User vs Organization)
  debug "Line $line_num: Checking owner type for $owner"
  owner_info=$(curl -s -H "$AUTH_HDR" "$API_URL/users/$owner")
  owner_type=$(printf '%s\n' "$owner_info" \
    | grep '"type"' \
    | head -n1 \
    | sed -E 's/.*"type": *"([^"]+)".*/\1/')
  
  debug "Line $line_num: Owner type: $owner_type"

  case "$owner_type" in
    Organization)
      create_url="$API_URL/orgs/$owner/repos"
      ;;
    User)
      create_url="$API_URL/user/repos"
      ;;
    *)
      echo "Error: could not determine owner type for '$owner'." 
      continue
      ;;
  esac

  # 2) Check repo existence
  status=$(
    curl -s -o /dev/null -w "%{http_code}" \
      -H "$AUTH_HDR" \
      "$API_URL/repos/$owner/$repo"
  )
  if [ "$status" -eq 200 ]; then
    echo "Exists: $owner/$repo"
  elif [ "$status" -eq 404 ]; then
    # build payload (auto_init if we’ll push a branch later)
    # Determine if this repo should be private or public
    # Line-specific flag takes precedence over global flag
    local this_repo_private
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
    
    if [ -n "$branch" ]; then
      payload="{\"name\":\"$repo\",\"private\":$this_repo_private,\"auto_init\":true}"
    else
      payload="{\"name\":\"$repo\",\"private\":$this_repo_private}"
    fi

    printf "Creating repo %s/%s ... " "$owner" "$repo"
    http_code=$(
      curl -s -o /dev/null -w "%{http_code}" \
        -H "$AUTH_HDR" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$create_url"
    )
    if [ "$http_code" -eq 201 ]; then
      echo "done."
    else
      echo "failed (HTTP $http_code)."
      continue
    fi
  else
    echo "Error checking $owner/$repo (HTTP $status)."
    continue
  fi

  # 3) Ensure branch exists
  if [ -n "$branch" ]; then
    ref_status=$(
      curl -s -o /dev/null -w "%{http_code}" \
        -H "$AUTH_HDR" \
        "$API_URL/repos/$owner/$repo/git/refs/heads/$branch"
    )
    if [ "$ref_status" -eq 200 ]; then
      echo "Branch exists: $branch"
    elif [ "$ref_status" -eq 404 ]; then
      printf "Creating branch %s ... " "$branch"
      code=$( create_branch "$owner" "$repo" "$branch" )
      if [ "$code" -eq 201 ]; then
        echo "done."
      else
        echo "failed (HTTP $code)."
      fi
    else
      echo "Error checking branch $branch (HTTP $ref_status)."
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
