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
## 2024-03-03 - [High] Path Traversal and Command Injection in Pipeline Execution
**Vulnerability:** `run-pipeline.sh` allowed arbitrary script paths via the `--script` flag or concise repository list, leading to execution of scripts outside the repository boundaries. Lack of input validation also posed a command injection risk.
**Learning:** Even if a tool is intended for local use, allowing user-controlled paths to be passed to execution commands without validation is dangerous. Input should be restricted to a safe character allow-list.
**Prevention:** Implement strict validation for all user-provided execution paths. Disallow absolute paths, `..` components, and shell metacharacters. Use a regex like `^[a-zA-Z0-9._/-]+$` for an allow-list of safe characters.
## 2026-02-24 - [High] JSON Injection and Path Traversal in Repository Management
**Vulnerability:** Repository specifications in `repos.list` were not validated for `..` components, leading to path traversal in workspace generation. Additionally, repository creation used manual string concatenation for JSON payloads, vulnerable to JSON injection if repository names contained double quotes.
**Learning:** Even if some inputs (like target directories) are validated, related inputs (like repository names or URLs) can still be exploited for similar attacks if they influence file paths or API requests. Manual JSON construction in shell scripts is highly error-prone and insecure.
**Prevention:** Always validate all user-provided components of a path for `..` traversal. Use `jq` with proper argument passing (`--arg`, `--argjson`) to construct JSON payloads securely instead of using string templates.
## 2026-05-22 - [Medium] Fragile and Insecure JSON Parsing in Shell Scripts
**Vulnerability:** Use of `grep` and `sed` for parsing GitHub API responses and manual string concatenation for building JSON payloads.
**Learning:** Manual JSON handling is error-prone and vulnerable to injection if variables contain special characters (like quotes). Line-based parsing fails if the API response format changes slightly (e.g. whitespace changes).
**Prevention:** Always use `jq` for both parsing and constructing JSON. Use `jq --arg` or `jq --argjson` to safely inject variables into JSON objects, ensuring proper escaping and preventing injection.
## 2027-02-27 - [High] Path Traversal in Repository Specifications
**Vulnerability:** Scripts derived local directory names from the `owner/repo` repository specification without checking for `..` components. An entry like `owner/repo/..` would cause the script to target the parent directory.
**Learning:** Validating explicit "target directory" arguments is insufficient if other parts of the input (like the repository name) are also used to construct file paths. Attackers will use the least-validated field to achieve the same traversal.
**Prevention:** Apply strict `..` validation to ALL user-provided tokens that contribute to path construction, including repository specifications, even if they are primarily intended as URLs or identifiers.
## 2027-02-28 - [Medium] Insecure Shell Interpolation in jq Filters
**Vulnerability:** Shell variables were interpolated directly into `jq` filter strings (e.g., `jq -r ".${field}"` or `if "'"$PERMISSIONS"'" == "all"`), potentially leading to injection vulnerabilities.
**Learning:** Interpolating shell variables into `jq` filters is insecure as it allows the variable content to be parsed as part of the filter logic. Simple replacement with `.[$field]` also fails for nested paths (e.g., `commit.sha`).
**Prevention:** Always use `jq`'s `--arg` or `--argjson` flags to pass values into the `jq` environment. For dynamic field access that may include nested paths, use `getpath($field | split("."))` to safely traverse the object.

## 2026-03-05 - [Medium] Argument Injection in Git Command Invocations
**Vulnerability:** Git commands like `git clone`, `git worktree add`, and `git push` were invoked with user-provided or variable-based arguments (e.g., branch names or repository URLs) without the `--` separator. This allowed an attacker to inject command-line flags (e.g., using a branch name like `-h`).
**Learning:** Positional arguments that start with a hyphen can be interpreted as options by many Unix commands, including Git. Relying on variable expansion without termination of option parsing is a common source of argument injection.
**Prevention:** Always use the `--` separator to terminate option parsing before passing positional arguments that may be user-controlled or contain arbitrary strings. Example: `git worktree add -- "$DEST" "$BRANCH"`.
