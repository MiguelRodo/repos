## 2024-10-27 - [High] Insecure Temporary File Creation for Debug Logs
**Vulnerability:** Predictable temporary file names used for debug logs in `/tmp` (e.g., `repos-debug-$(date +%Y%m%d-%H%M%S)-$$.log`).
**Learning:** This pattern is vulnerable to symlink attacks, where an attacker can pre-create a symlink with the predicted name pointing to a sensitive file, causing the script to overwrite it when run with debug flags.
**Prevention:** Use `mktemp` to create temporary files securely with restrictive permissions (0600) and unpredictable names. For portability between Linux and macOS, ensure the `XXXXXX` template is at the end of the filename (no suffix).
## 2025-02-21 - Insecure Temporary Debug Logs
**Vulnerability:** Predictable temporary file names for debug logs in `/tmp` using `$$` and `date`.
**Learning:** Using `$$` and `date` to generate temporary filenames is insecure because it's predictable, allowing for symlink attacks. An attacker can pre-create a symlink with the predicted name pointing to a sensitive file (e.g., `~/.ssh/authorized_keys`), and the script will append to it.
**Prevention:** Always use `mktemp` to create temporary files. `mktemp` ensures exclusive creation, non-predictability, and restrictive permissions (0600). For maximum portability across macOS and Linux, ensure the template (e.g., `XXXXXX`) is at the very end of the argument to `mktemp`.
## 2026-02-23 - [High] Path Traversal in Workspace Generation and Pipeline Execution
**Vulnerability:** User-specified target directories in `repos.list` were not validated in `vscode-workspace-add.sh` and `run-pipeline.sh`, allowing malicious entries to point to arbitrary locations outside the workspace.
**Learning:** Even if the primary tool (`clone-repos.sh`) validates input, secondary tools that parse the same input must also implement consistent validation, especially if they generate configuration (`entire-project.code-workspace`) that is subsequently trusted by other tools (`run-pipeline.sh`).
**Prevention:** Centralize input validation where possible, or ensure all entry points for user-controlled data implement the same strict validation rules. Always disallow absolute paths and `..` components in user-provided directory names.
## 2026-02-24 - [Medium] Insecure and Fragile JSON Parsing/Construction in Bash Scripts
**Vulnerability:** Use of `grep` and `sed` for parsing GitHub API responses and string concatenation for constructing JSON payloads in `create-repos.sh`. This is brittle and potentially vulnerable to injection if repository or branch names contain special characters.
**Learning:** For scripts interacting with APIs, manual JSON handling is a significant security and robustness risk. Even for "internal" scripts, following the principle of "trust nothing, verify everything" requires using established tools like `jq`.
**Prevention:** Standardize on using `jq` for all JSON operations. Use `jq -r` for robust parsing and `jq --arg`/`jq --argjson` for secure, escaped payload construction. Ensure `jq` is added to prerequisite checks in parent scripts.
