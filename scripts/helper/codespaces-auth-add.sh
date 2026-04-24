#!/usr/bin/env bash
#
# scripts/codespaces-auth-add.sh
# Adds GitHub repo permissions into .devcontainer/devcontainer.json
# Compatible with Bash 3.2

set -o errexit   # same as -e
set -o nounset   # same as -u
set -o pipefail

# Never prompt for credentials (prevents stdin reads that can kill the loop)
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/false
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -oBatchMode=yes}"

git() { command git "$@" </dev/null; }

# ——— Defaults ———————————————————————————————————————————————
# Validate devcontainer path to prevent path traversal
validate_devcontainer_path() {
  local path="$1"
  if [ -n "$path" ]; then
    case "$path" in
      /*|*..*)
        printf "Error: devcontainer path cannot be absolute or contain '..': %s\n" "$path" >&2
        return 1
        ;;
    esac
  fi
  return 0
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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DEVCONTAINER_PATHS=()  # Array of devcontainer.json paths to update
if [ ! -f "$PROJECT_ROOT/repos.list" ] && [ -f "$PROJECT_ROOT/repos-to-clone.list" ]; then
  REPOS_FILE="$PROJECT_ROOT/repos-to-clone.list"
else
  REPOS_FILE="$PROJECT_ROOT/repos.list"
fi
REPOS_OVERRIDE=""
PERMISSIONS="default"    # default | all | contents
DRY_RUN=0
RAW_LIST=""
VALID_LIST=""
FORCE_TOOL=""   # if set via -t|--tool (one of jq, python, python3, py, rscript)

# ——— Usage ————————————————————————————————————————————————
usage(){
  cat <<'EOF'
Usage: codespaces-auth-add.sh [options]

Options:
  -f, --file <path>        Read repos from <path> (default: repos.list)
  -r, --repo <a,b,c...>    Comma-separated repos; overrides the file
  -d, --devcontainer <path> Path to devcontainer.json (can be specified multiple times)
                           If not specified, no files are updated (opt-in behavior)
  --permissions all        Use "permissions":"write-all"
  --permissions contents   Use "permissions":{"contents":"write"}
  -t, --tool <name>        Force update mechanism: jq, python, python3, py, or Rscript
  -n, --dry-run            Print resulting devcontainer.json to stdout
  -h, --help               Show this help and exit

File format (same as clone-repos.sh):
  - Lines can be: owner/repo, https://github.com/owner/repo, or @branch
  - @branch lines inherit from the "fallback repo" (initially the current repo)
  - After each non-@branch line, fallback updates to that repo
  - Branch syntax: owner/repo@branch is supported
  - Target directories and options (like --no-worktree, -a) are ignored
  - Lines starting with '#' or blank lines are skipped

Examples:
  codespaces-auth-add.sh -d .devcontainer/devcontainer.json
  codespaces-auth-add.sh -d path1/devcontainer.json -d path2/devcontainer.json
  
  @data-tidy              # Uses current repo
  SATVILab/projr          # Explicit repo, becomes new fallback
  @dev                    # Uses SATVILab/projr (current fallback)
  SATVILab/Analysis@test  # Explicit repo with branch, becomes new fallback
  @feature                # Uses SATVILab/Analysis (current fallback)
EOF
  exit "${1:-1}"
}

# ——— Default permissions block —————————————————————————————————
default_permissions_block(){
  cat <<'EOF'
{
  "permissions": {
    "actions": "write",
    "contents": "write",
    "packages": "read",
    "workflows": "write"
  }
}
EOF
}

# ——— Parse CLI args ————————————————————————————————————————
parse_args(){
  while [ $# -gt 0 ]; do
    case "$1" in
      -f|--file)
        shift; [ $# -gt 0 ] || { printf "Error: Missing file\n" >&2; usage; }
        REPOS_FILE="$1"; shift
        ;;
      -r|--repo)
        shift; [ $# -gt 0 ] || { printf "Error: Missing repo list\n" >&2; usage; }
        REPOS_OVERRIDE="$1"; shift
        ;;
      -d|--devcontainer)
        shift; [ $# -gt 0 ] || { printf "Error: Missing devcontainer path\n" >&2; usage; }
        validate_devcontainer_path "$1" || exit 1
        DEVCONTAINER_PATHS+=("$1"); shift
        ;;
      --permissions)
        shift; [ $# -gt 0 ] || { printf "Error: Missing type\n" >&2; usage; }
        case "$1" in all) PERMISSIONS="all" ;; contents) PERMISSIONS="contents" ;;
          *) printf "Error: Unknown permissions: %s\n" "$1" >&2; usage ;;
        esac
        shift
        ;;
      -t|--tool)
        shift; [ $# -gt 0 ] || { printf "Error: Missing tool name\n" >&2; usage; }
        case "$1" in
          jq|python|python3|py|rscript|Rscript) 
            [ "$1" = "rscript" ] && FORCE_TOOL="Rscript" || FORCE_TOOL="$1"
            ;;          *) printf "Error: Unsupported tool: %s\n" "$1" >&2; usage ;;
        esac
        shift
        ;;
      -n|--dry-run)
        DRY_RUN=1; shift
        ;;
      -h|--help)
        usage 0
        ;;
      *)
        printf "Error: Unknown option: %s\n" "$1" >&2; usage
        ;;
    esac
  done
}

# ——— Helper to trim leading and trailing whitespace —————————————
trim_whitespace() {
  local str="$1"
  str="${str#"${str%%[![:space:]]*}"}"
  str="${str%"${str##*[![:space:]]}"}"
  printf '%s\n' "$str"
}

# ——— Helper to normalise a remote URL to https format —————————————
normalise_remote_to_https() {
  # Convert a remote URL to https://host/owner/repo (no .git)
  local url="$1" host path
  case "$url" in
    http://*|https://*)
      url="${url%.git}"
      # Strip embedded credentials (e.g. http://user:pass@host/...)
      # to prevent leaking tokens in logs or workspace files.
      url="$(printf '%s\n' "$url" | sed 's|^\(https\?://\)[^/]*@|\1|')"
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

# ——— Get current repo's remote as https URL —————————————————————————
get_current_repo_remote_https() {
  cd "$PROJECT_ROOT" || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf "Error: not inside a Git working tree; cannot derive fallback repo.\n" >&2
    return 1
  }

  local url="" first="" remotes
  remotes="$(git remote 2>/dev/null || true)"
  
  # Use printf, grep -e, and git remote get-url -- to prevent argument injection
  # and misinterpretation of variables starting with a hyphen
  if printf '%s\n' "$remotes" | grep -qx -e 'origin'; then
    if ! url="$(git remote get-url --push -- origin 2>/dev/null)"; then
      url="$(git remote get-url -- origin 2>/dev/null || true)"
    fi
  fi

  if [ -z "$url" ] && [ -n "$remotes" ]; then
    first="$(printf '%s\n' "$remotes" | head -n1)"
    if [ -n "$first" ]; then
      if ! url="$(git remote get-url --push -- "$first" 2>/dev/null)"; then
        url="$(git remote get-url -- "$first" 2>/dev/null || true)"
      fi
    fi
  fi

  [ -z "$url" ] && { printf "Error: no Git remotes found in the current repository.\n" >&2; return 1; }
  local normalized
  normalized="$(normalise_remote_to_https "$url")" || return $?

  # Validate for path traversal
  case "$normalized" in
    *..*)
      printf "Error: current repository remote contains path traversal: %s\n" "$normalized" >&2
      return 1
      ;;
  esac

  printf '%s\n' "$normalized"
}

# ——— Extract owner/repo from https URL —————————————————————————————
extract_owner_repo_from_https() {
  local url="$1"
  url="${url%/}"
  url="${url%.git}"
  case "$url" in
    https://github.com/*) url="${url#https://github.com/}" ;;
    https://*/*) url="${url#https://*/}" ;;
  esac
  printf '%s\n' "$url"
}

# ——— Normalise a line to owner/repo —————————————————————————————
# Now handles @branch lines using fallback repo
# Args: line, fallback_repo_https
normalise(){
  local line="$1" fallback_repo_https="$2"
  local raw first
  
  # Trim leading/trailing whitespace
  line=$(trim_whitespace "$line")
  
  # Parse first token
  set -f
  set -- $line
  set +f
  first="$1"
  
  case "$first" in
    @*)
      # This is a @branch line - use fallback repo
      local branch="${first#@}"
      if [ -z "$branch" ] || [[ "$branch" == -* ]] || ! git check-ref-format --allow-onelevel "$branch"; then
        printf "Error: '%s' is not a valid Git branch name.\n" "$branch" >&2
        return 1
      fi
      if [ -z "$fallback_repo_https" ]; then
        printf "Warning: @branch line without fallback repo: %s\n" "$line" >&2
        return 1
      fi
      extract_owner_repo_from_https "$fallback_repo_https"
      ;;
    *)
      # Regular repo spec
      raw="$first"
      raw="${raw%%@*}"            # strip @branch
      raw="${raw%/}"              # strip trailing slash
      raw="${raw%.git}"           # strip .git
      case "$raw" in
        https://github.com/*) raw="${raw#https://github.com/}" ;;
        https://*/*) raw="${raw#https://*/}" ;;
        */*) : ;;  # already in owner/repo format
        *) return 1 ;;  # invalid format
      esac
      printf '%s\n' "$raw"
      ;;
  esac
}

# ——— Validate owner/repo (no datasets/ and no ..) ————————————————
validate(){
  local repo_spec="$1"
  # 1. No path traversal
  case "$repo_spec" in
    *..*) return 1 ;;
  esac

  # 2. Must be in owner/repo format
  if [[ ! "$repo_spec" =~ ^[^/]+/[^/]+$ ]]; then
    return 1
  fi

  # 3. Specifically exclude the "datasets" owner
  local owner="${repo_spec%%/*}"
  if [ "$owner" = "datasets" ]; then
    return 1
  fi

  # 4. Valid characters (alphanumeric, hyphen, underscore, dot)
  # and doesn't start with hyphen (prevent arg injection)
  local VALID_PATTERN="^[a-zA-Z0-9][a-zA-Z0-9._-]*$"
  local repo="${repo_spec#*/}"
  if [[ ! "$owner" =~ $VALID_PATTERN ]] || [[ ! "$repo" =~ $VALID_PATTERN ]]; then
    return 1
  fi

  printf '%s\n' "$repo_spec"
}

# ——— Build RAW_LIST from override or file ————————————————————————
build_raw_list(){
  if [ -n "$REPOS_OVERRIDE" ]; then
    # For override mode, no @branch syntax is expected
    local IFS=','
    set -f
    for repo in $REPOS_OVERRIDE; do
      local normalized
      normalized=$(normalise "$repo" "") && RAW_LIST+="$normalized"$'\n'
    done
    set +f
  else
    [ -f "$REPOS_FILE" ] || { printf "Error: File not found: %s\n" "$REPOS_FILE" >&2; exit 1; }
    
    # Initialize fallback repo to current repo's remote
    local fallback_repo_https current_repo_https
    current_repo_https=$(get_current_repo_remote_https) || current_repo_https=""
    fallback_repo_https="$current_repo_https"
    
    while IFS= read -r line || [ -n "$line" ]; do
      # Trim and skip comments/blanks
      local trimmed
      trimmed=$(trim_whitespace "$line")
      case "$trimmed" in
        ''|\#*) continue ;;
      esac
      # Strip inline comments
      case "$trimmed" in
        *" # "*) trimmed="${trimmed%% # *}" ;;
        *" #"*) trimmed="${trimmed%% #*}" ;;
      esac
      trimmed=$(trim_whitespace "$trimmed")
      trimmed="${trimmed%$'\r'}"
      [ -z "$trimmed" ] && continue
      
      # Parse first token
      set -f
      set -- $trimmed
      set +f
      local first="$1"
      
      case "$first" in
        @*)
          # @branch line - use current fallback
          local normalized
          if normalized=$(normalise "$trimmed" "$fallback_repo_https"); then
            RAW_LIST+="$normalized"$'\n'
          fi
          # @branch lines do NOT change the fallback
          ;;
        *)
          # Regular repo line - extract and update fallback
          # Check for branch in repo spec
          local branch_part=""
          case "$first" in *@*) branch_part="${first##*@}" ;; esac
          if [ -n "$branch_part" ] && ( [[ "$branch_part" == -* ]] || ! git check-ref-format --allow-onelevel "$branch_part" ); then
            printf "Error: '%s' is not a valid Git branch name.\n" "$branch_part" >&2
            exit 1
          fi

          # Validate repo_spec to prevent path traversal and argument injection
          case "${first%@*}" in
            -*|*..*)
              printf "Error: repository spec cannot start with a hyphen or contain '..': %s\n" "$first" >&2
              exit 1
              ;;
          esac
          local normalized repo_no_branch repo_https
          if normalized=$(normalise "$trimmed" ""); then
            RAW_LIST+="$normalized"$'\n'
            # Update fallback: extract repo spec (first token), remove @branch part
            repo_no_branch="${first%%@*}"
            repo_no_branch="${repo_no_branch%.git}"
            # Convert to https format
            case "$repo_no_branch" in
              http://*|https://*|/*|[a-zA-Z]:/*|file://*)
                repo_https=$(normalise_remote_to_https "$repo_no_branch")
                ;;
              */*)
                repo_https="https://github.com/$repo_no_branch"
                ;;
              *)
                repo_https=""
                ;;
            esac
            [ -n "$repo_https" ] && fallback_repo_https="$repo_https"
          fi
          ;;
      esac
    done <"$REPOS_FILE"
  fi
}

# ——— Filter RAW_LIST → VALID_LIST ——————————————————————————————
filter_valid_list(){
  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    if vr=$(validate "$repo"); then
      VALID_LIST+="$vr"$'\n'
    else
      printf "Skipping invalid or disallowed: %s\n" "$repo" >&2
    fi
  done <<<"$RAW_LIST"

  [ -n "$VALID_LIST" ] || { printf "Error: No valid repos found.\n" >&2; exit 1; }
}

# ——— Build a newline-delimited JSON array for jq ———————————————
build_jq_array(){
  printf '%s\n' "$VALID_LIST" \
    | jq -R 'select(length>0)' \
    | jq -s .
}

# ——— Generate the per-repo permissions object via jq —————————————
build_jq_obj(){
  local arr_json="$1"
  jq -n --argjson arr "$arr_json" --arg perms "$PERMISSIONS" '
    reduce $arr[] as $repo ({}; 
      . + {
        ($repo): (
          if $perms == "all" then
            { permissions:"write-all" }
          elif $perms == "contents" then
            { permissions:{ contents:"write" } }
          else
            {
              permissions: {
                actions:  "write",
                contents: "write",
                packages: "read",
                workflows:"write"
              }
            }
          end
        )
      }
    )
  '
}

# ——— Merge into devcontainer.json (jq variant) —————————————————————
update_with_jq(){
  local file="$1"
  local arr_json repos_obj tmp

  arr_json=$(build_jq_array)
  repos_obj=$(build_jq_obj "$arr_json")

  if [ ! -f "$file" ]; then
    jq -n --argjson repos "$repos_obj" '
      { customizations:{ codespaces:{ repositories:$repos } } }
    ' >"$file"
  else
    tmp="$(mktemp "$(get_temp_dir)/repos-auth-XXXXXX")"
    trap 'rm -f -- "$tmp"' EXIT
    jq --argjson repos "$repos_obj" '
      .customizations.codespaces.repositories
        |= ( (. // {}) + $repos )
    ' -- "$file" >"$tmp" && mv -- "$tmp" "$file"
    trap - EXIT
  fi

  printf "Updated '%s' with jq.\n" "$file"
}

# ——— Python (or python3 / py) fallback, JSONC-aware + trailing-comma strip —————
# Usage: update_with_python <devfile> <python-cmd>
update_with_python(){
  local file="$1"
  local py_cmd="${2:-python}"
  local arr_json repos_obj

  # 1) Build the JSON array & object as jq would
  arr_json=$(build_jq_array)
  repos_obj=$(build_jq_obj "$arr_json")

  # 2) Export it so the Python process can see it
  export REPOS_JSON="$repos_obj"

  # 3) Run Python: strip comments & trailing commas, parse, merge, emit JSON
  # Using -- after the interpreter or - ensures that $file is not interpreted as a flag
  "$py_cmd" - "$file" <<'PYCODE'
import sys, json, re, os

def strip_jsonc(text):
    # Match strings or comments.
    # For single-line comments, we use [^\n]* to avoid matching across lines
    # even when re.DOTALL is active.
    pattern = re.compile(
        r'(?P<string>"([^"\\\n]|\\.)*")|(?P<comment_ml>/\*.*?\*/)|(?P<comment_sl>//[^\n]*)|(?P<comma>,\s*(?=[}\]]))',
        re.DOTALL | re.MULTILINE
    )
    def replace(match):
        if match.group('string'):
            return match.group('string')
        else:
            return ""
    return pattern.sub(replace, text)

fname = sys.argv[1]
with open(fname, 'r') as f:
    text = f.read()

# Strip comments and trailing commas properly (handling strings)
text = strip_jsonc(text)

# Now parse clean JSON
data = json.loads(text)

# Load the new repos block from the env var
new = json.loads(os.environ['REPOS_JSON'])

# Merge into data
cs = data.setdefault('customizations', {})
cp = cs.setdefault('codespaces', {})
repos = cp.setdefault('repositories', {})
repos.update(new)

# Output the merged JSON
print(json.dumps(data, indent=2))
PYCODE
}

# In your update_devfile(), make sure you capture that stdout into the file:
# update_with_python "$DEVFILE" "$tool" > "$DEVFILE"
# echo "Updated '$DEVFILE' with $tool."




# ——— Rscript fallback (env-var merge, no duplicates) —————————————————————
update_with_rscript(){
  local file="$1"
  local arr_json repos_obj

  # Build the same JSON array & object as jq
  arr_json=$(build_jq_array)
  repos_obj=$(build_jq_obj "$arr_json")

  # Pass the JSON via env var to Rscript
  REPOS_OBJ="$repos_obj" Rscript --vanilla - "$file" <<'RSCRIPT'
library(jsonlite)

# Read args
args <- commandArgs(trailingOnly=TRUE)
file <- args[1]

# Parse the new repos block from the environment
repos_json <- Sys.getenv("REPOS_OBJ")
new <- fromJSON(repos_json)

# Load or initialise existing JSON
if (file.exists(file)) {
  data <- tryCatch(fromJSON(file), error = function(e) list())
} else {
  data <- list()
}

# Drill into nested lists, creating if missing
cs <- data$customizations;    if (is.null(cs))    cs <- list()
cp <- cs$codespaces;         if (is.null(cp))    cp <- list()
repos <- cp$repositories;    if (is.null(repos)) repos <- list()

# Merge by name (overwrite existing, no .1 duplicates)
repos[names(new)] <- new

# Rebuild and write back
cp$repositories     <- repos
cs$codespaces       <- cp
data$customizations <- cs

write_json(data, file, pretty = TRUE, auto_unbox = TRUE)
RSCRIPT

  printf "Updated '%s' with Rscript.\n" "$file"
}

# ——— Dispatch to the first available tool ——————————————————————
update_devfile(){
  local devfile="$1"
  local tool=""

  # 1) Pick the forced tool or auto-detect
  if [ -n "$FORCE_TOOL" ]; then
    command -v "$FORCE_TOOL" >/dev/null 2>&1 \
      || { printf "Error: forced tool '%s' not found.\n" "$FORCE_TOOL" >&2; exit 1; }
    tool="$FORCE_TOOL"
  else
    for candidate in jq python python3 py Rscript; do
      if command -v "$candidate" >/dev/null 2>&1; then
        tool="$candidate"; break
      fi
    done
    [ -n "$tool" ] || { printf "Error: No JSON tool found.\n" >&2; exit 1; }
  fi

  # 2) Invoke the updater
  case "$tool" in
    jq)
      update_with_jq "$devfile"
      ;;
    python|python3|py)
      if [ "$DRY_RUN" -eq 1 ]; then
        # In dry-run, just print what Python would output
        update_with_python "$devfile" "$tool"
      else
        # Safely write via a temporary file, then move into place
        tmp="$(mktemp "$(get_temp_dir)/repos-auth-XXXXXX")"
        trap 'rm -f -- "$tmp"' EXIT
        update_with_python "$devfile" "$tool" > "$tmp"
        mv -- "$tmp" "$devfile"
        trap - EXIT
        printf "Updated '%s' with %s.\n" "$devfile" "$tool"
      fi
      ;;
    Rscript)
      update_with_rscript "$devfile"
      ;;
  esac

  # 3) In dry-run mode, show the result
  if [ "$DRY_RUN" -eq 1 ]; then
    printf "=== DRY-RUN OUTPUT for %s ===\n" "$devfile"
    cat -- "$devfile"
  fi
}

# ——— Main ————————————————————————————————————————————————
main(){
  parse_args "$@"
  
  # If no devcontainer paths specified, exit with message (opt-in behavior)
  if [ ${#DEVCONTAINER_PATHS[@]} -eq 0 ]; then
    printf "No devcontainer.json paths specified. Use -d/--devcontainer to specify paths to update.\n" >&2
    exit 0
  fi
  
  build_raw_list
  filter_valid_list

  printf "DEBUG: will add the following repos:\n" >&2
  printf '%s' "$VALID_LIST" >&2

  # Process each devcontainer.json path
  for devfile in "${DEVCONTAINER_PATHS[@]}"; do
    # Convert to absolute path if relative
    if [[ ! "$devfile" = /* ]]; then
      # Use current working directory for relative paths
      devfile="$(pwd)/$devfile"
    fi
    
    if [ ! -f "$devfile" ]; then
      printf "Error: devcontainer.json not found at %s\n" "$devfile" >&2
      exit 1
    fi
    
    printf "Processing %s...\n" "$devfile" >&2
    update_devfile "$devfile"
  done
}

main "$@"
