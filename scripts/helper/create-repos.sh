#!/usr/bin/env bash
# create-repos.sh — create GitHub repos (with branches) from a list
# Requires: bash 3.2+, curl

set -o errexit   # same as -e
set -o nounset   # same as -u
set -o pipefail

# ── CONFIG & USAGE ─────────────────────────────────────────────────────────────
if [ ! -f "repos.list" ] && [ -f "repos-to-clone.list" ]; then
  REPOS_FILE="repos-to-clone.list"
else
  REPOS_FILE="repos.list"
fi

usage() {
  cat <<EOF
Usage: $0 [-f <repo-list>] [-p|--public]

  -f FILE         read lines from FILE (default: repos.list)
  -p, --public    create repos as public (default: private)
  -h, --help      show this message and exit

Each non-blank, non-# line of <repo-list> can be:
  owner/repo[@branch] [target_directory]
    Creates/checks the repo and optionally checks the branch exists.
  @branch [target_directory]
    Checks if the branch exists on the "fallback repo" (the most recently
    processed owner/repo line). If not in a git repo, fallback starts empty.

Target directories are informational only (used by clone-repos.sh).
EOF
  exit 1
}

PRIVATE_FLAG=true
while [ $# -gt 0 ]; do
  case $1 in
    -f)           shift; REPOS_FILE="$1"; shift ;;
    -p|--public)  PRIVATE_FLAG=false; shift ;;
    -h|--help)    usage ;;
    *)            echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[ -f "$REPOS_FILE" ] || { echo "Error: '$REPOS_FILE' not found." >&2; exit 1; }

# ── CREDENTIALS WITH FALLBACK (will be retrieved only if needed) ────────────────
get_credentials() {
  if [ -z "${GH_TOKEN-}" ] || [ -z "${GH_USER-}" ]; then
    creds=$(
      printf 'url=https://github.com\n\n' \
        | git -c credential.interactive=false credential fill
    )
    [ -z "${GH_USER-}" ] && \
      GH_USER=$(printf '%s\n' "$creds" | awk -F= '/^username=/ {print $2}')
    [ -z "${GH_TOKEN-}" ] && \
      GH_TOKEN=$(printf '%s\n' "$creds" | awk -F= '/^password=/ {print $2}')
    : "${GH_USER:?Could not retrieve GitHub username}"
    : "${GH_TOKEN:?Could not retrieve GitHub token}"
  fi
}

API_URL="https://api.github.com"
if $PRIVATE_FLAG; then JSON_PRIVATE=true; else JSON_PRIVATE=false; fi

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
get_current_repo_info || true  # Don't fail if not in a git repo


while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|\#*) continue ;; esac

  repo_spec=${line%%[[:space:]]*}
  
  # Handle @branch lines (worktrees) - check branch on fallback repo
  case "$repo_spec" in
    @*)
      branch=${repo_spec#@}
      # Extract branch name, removing any options like --no-worktree
      branch=${branch%%[[:space:]]*}
      
      if [ -z "$fallback_owner" ] || [ -z "$fallback_repo" ]; then
        echo "Warning: @$branch cannot be processed - no previous owner/repo line found to use as fallback repository; skipping branch check."
        continue
      fi
      
      # Get credentials if needed
      get_credentials
      AUTH_HDR="Authorization: token $GH_TOKEN"
      
      # Check if branch exists on fallback repo
      ref_status=$(
        curl -s -o /dev/null -w "%{http_code}" \
          -H "$AUTH_HDR" \
          "$API_URL/repos/$fallback_owner/$fallback_repo/git/refs/heads/$branch"
      )
      if [ "$ref_status" -eq 200 ]; then
        echo "Branch exists: $branch"
      elif [ "$ref_status" -eq 404 ]; then
        printf "Creating branch %s on %s/%s ... " "$branch" "$fallback_owner" "$fallback_repo"
        code=$( create_branch "$fallback_owner" "$fallback_repo" "$branch" )
        if [ "$code" -eq 201 ]; then
          echo "done."
        else
          echo "failed (HTTP $code)."
        fi
      else
        echo "Error checking branch $branch on $fallback_owner/$fallback_repo (HTTP $ref_status)."
      fi
      
      # @branch lines don't change the fallback
      continue
      ;;
  esac
  
  # Skip local remotes (file:// URLs and absolute paths)
  case "$repo_spec" in
    file://*|/*)
      echo "Skipping local remote: $repo_spec"
      continue
      ;;
  esac
  
  # Skip non-GitHub HTTPS/SSH URLs
  case "$repo_spec" in
    https://github.com/*|git@github.com:*|ssh://git@github.com/*)
      # This is a GitHub URL, process it
      ;;
    https://*|git@*|ssh://*)
      # This is a non-GitHub remote URL
      echo "Skipping non-GitHub remote: $repo_spec"
      continue
      ;;
  esac
  
  repo_path=${repo_spec%@*}
  owner=${repo_path%%/*}
  repo=${repo_path##*/}
  case "$repo_spec" in *@*) branch=${repo_spec##*@} ;; *) branch="" ;; esac

  # Get credentials only when we need them (for GitHub repos)
  get_credentials
  AUTH_HDR="Authorization: token $GH_TOKEN"

  # 1) Determine owner type (User vs Organization)
  owner_info=$(curl -s -H "$AUTH_HDR" "$API_URL/users/$owner")
  owner_type=$(printf '%s\n' "$owner_info" \
    | grep '"type"' \
    | head -n1 \
    | sed -E 's/.*"type": *"([^"]+)".*/\1/')

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
    if [ -n "$branch" ]; then
      payload="{\"name\":\"$repo\",\"private\":$JSON_PRIVATE,\"auto_init\":true}"
    else
      payload="{\"name\":\"$repo\",\"private\":$JSON_PRIVATE}"
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
