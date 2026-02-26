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
## 2026-02-24 - [High] JSON Injection and Path Traversal in Repository Management
**Vulnerability:** Repository specifications in `repos.list` were not validated for `..` components, leading to path traversal in workspace generation. Additionally, repository creation used manual string concatenation for JSON payloads, vulnerable to JSON injection if repository names contained double quotes.
**Learning:** Even if some inputs (like target directories) are validated, related inputs (like repository names or URLs) can still be exploited for similar attacks if they influence file paths or API requests. Manual JSON construction in shell scripts is highly error-prone and insecure.
**Prevention:** Always validate all user-provided components of a path for `..` traversal. Use `jq` with proper argument passing (`--arg`, `--argjson`) to construct JSON payloads securely instead of using string templates.
