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

## 2027-02-27 - [High] Path Traversal in Repository Specifications
**Vulnerability:** Scripts derived local directory names from the `owner/repo` repository specification without checking for `..` components. An entry like `owner/repo/..` would cause the script to target the parent directory.
**Learning:** Validating explicit "target directory" arguments is insufficient if other parts of the input (like the repository name) are also used to construct file paths. Attackers will use the least-validated field to achieve the same traversal.
**Prevention:** Apply strict `..` validation to ALL user-provided tokens that contribute to path construction, including repository specifications, even if they are primarily intended as URLs or identifiers.
## 2026-05-22 - [Medium] Fragile and Insecure JSON Parsing in Shell Scripts
**Vulnerability:** Use of `grep` and `sed` for parsing GitHub API responses and manual string concatenation for building JSON payloads.
**Learning:** Manual JSON handling is error-prone and vulnerable to injection if variables contain special characters (like quotes). Line-based parsing fails if the API response format changes slightly (e.g. whitespace changes).
**Prevention:** Always use `jq` for both parsing and constructing JSON. Use `jq --arg` or `jq --argjson` to safely inject variables into JSON objects, ensuring proper escaping and preventing injection.
