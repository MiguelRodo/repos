#!/usr/bin/env bash

# strict mode
set -o errexit   # bail on error
set -o nounset   # undefined var → error
set -o pipefail  # catch failures in pipes
IFS=$'\n\t'      # only split on newline and tab

# 0. Ensure Rscript exists
if ! command -v Rscript >/dev/null 2>&1; then
  echo "❌ Rscript not found. Please install Rscript." >&2
  exit 1
fi
# 4. Parse all the "path" entries via jq
if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq not found. Please install jq to parse the workspace file." >&2
  exit 1
fi

# 1. Where the user ran this script
INVOKE_DIR="$PWD"

# 2. Where this script lives (to locate the workspace file)
SCRIPT_DIR="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"

# 3. Locate the workspace JSON (two levels up from scripts/helper/)
WS1="$SCRIPT_DIR/../../entire-project.code-workspace"
WS2="$SCRIPT_DIR/../../EntireProject.code-workspace"
if   [ -f "$WS1" ]; then WORKSPACE_FILE="$WS1"
elif [ -f "$WS2" ]; then WORKSPACE_FILE="$WS2"
else
  printf "❌ No .code‑workspace file found in %s\n" "$(cd "$SCRIPT_DIR/../.." && pwd)" >&2
  exit 1
fi

# 4. Parse all the "path" entries into a Bash array
FOLDERS=()
while IFS= read -r folder; do
  # Validate folder path to prevent traversal
  case "$folder" in
    /*|..|*/..|../*|*/../*)
      # If absolute or contains ".." anywhere, only allow exactly one leading "../"
      # followed by a single directory name (no further traversal)
      is_valid=false
      if [[ "$folder" == ../* ]]; then
        remainder="${folder#../}"
        if [[ "$remainder" != */* && "$remainder" != *..* && "$remainder" != "" ]]; then
          is_valid=true
        fi
      fi

      if [ "$is_valid" = false ]; then
        printf "⚠️ Skipping invalid workspace folder path (unauthorized '..' or absolute): %s\n" "$folder" >&2
        continue
      fi
      ;;
  esac
  FOLDERS+=("$folder")
done < <(jq -r '.folders[].path' -- "$WORKSPACE_FILE")

# 5. Your provided helpers, tweaked to operate per‑folder
restore_renv() {
  local rel="$1"
  local tgt="$INVOKE_DIR/$rel"

  printf "🔄 [%s] Found renv.lock – restoring with renv…\n" "$rel"
  # run everything *inside* that folder
  cd -- "$tgt" || { printf "⚠️ cannot cd to %s\n" "$tgt" >&2; return 1; }

  printf "⚙️  Checking for renv…\n"
  cd -- ".." || exit 1
  Rscript --vanilla -e '
    if (!requireNamespace("renv", quietly=TRUE))
      install.packages("renv", repos="https://cloud.r-project.org")
  '
  cd -- "$tgt" || exit 1

  printf "⚙️ Upgrade renv…\n"
  Rscript --vanilla -e 'renv::upgrade()'

  printf "⚙️  Checking for gitcreds…\n"
  Rscript --vanilla -e '
    if (!requireNamespace("gitcreds", quietly=TRUE))
      renv::install("gitcreds")
  '

  printf "🔗  Installing UtilsProjrMR…\n"
  Rscript --vanilla -e 'renv::install("MiguelRodo/UtilsProjrMR")'

  printf "🔄  Updating & restoring project via UtilsProjrMR…\n"
  Rscript --vanilla -e 'UtilsProjrMR::projr_renv_restore_and_update()'

  printf "✅ [%s] Done.\n" "$rel"
  # back to where we started
  cd -- "$INVOKE_DIR" || exit 1
}

restore_pak_desc() {
  local rel="$1"
  local tgt="$INVOKE_DIR/$rel"

  printf "🔄 [%s] Found DESCRIPTION – installing via pak…\n" "$rel"
  cd -- "$tgt" || { printf "⚠️ cannot cd to %s\n" "$tgt" >&2; return 1; }

  Rscript --vanilla -e '
    if (!requireNamespace("pak", quietly=TRUE))
      install.packages("pak", repos="https://cloud.r-project.org");
    pak::local_install_dev_deps()
  ' || return 1

  printf "✅ [%s] pak install done.\n" "$rel"
  cd -- "$INVOKE_DIR" || exit 1
}

# 6. Loop over each folder and try restoring
for rel in "${FOLDERS[@]}"; do
  TARGET="$INVOKE_DIR/$rel"

  if [ ! -d "$TARGET" ]; then
    printf "⚠️ [%s] Folder not found – skipping\n" "$rel"
    continue
  fi

  if [ -f "$TARGET/renv.lock" ]; then
    restore_renv "$rel" \
      || printf "⚠️ [%s] renv restore failed – moving on\n" "$rel"
  elif [ -f "$TARGET/DESCRIPTION" ]; then
    restore_pak_desc "$rel" \
      || printf "⚠️ [%s] pak install failed – moving on\n" "$rel"
  else
    printf "ℹ️ [%s] No renv.lock or DESCRIPTION – skipping\n" "$rel"
  fi
done

echo "✅ All done across all folders!"
