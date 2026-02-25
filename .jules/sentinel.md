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
## 2027-02-25 - [High] Secondary Path Traversal in Pipeline Execution and Dependency Installation
**Vulnerability:** Downstream scripts (`run-pipeline.sh` and `install-r-deps.sh`) trusted paths read from `.code-workspace` files without validation. An attacker could bypass previous `repos.list` validations by providing a malicious workspace file or exploiting inconsistencies in validation logic between generation and consumption.
**Learning:** Validating input at the source is insufficient if intermediate artifacts are trusted blindly. Security checks must be applied at every trust boundary, especially before performing file system operations or command execution.
**Prevention:** Implement defense-in-depth by validating paths at every consumption point. For this project, workspace paths should allow exactly one leading `..` (for sibling repos) but reject absolute paths and any other `..` components.
