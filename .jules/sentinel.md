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

## 2028-04-10 - [Medium] Unintended Glob Expansion and Insecure Output Handling in Shell Scripts
**Vulnerability:** Use of `set -- $variable` without disabling glob expansion and `echo "$variable"` for user-provided input.
**Learning:** Shell scripts that parse external configuration files by word-splitting into positional parameters (`set -- $line`) will unintentionally expand glob characters (`*`, `?`) if they match local files. Additionally, `echo` can interpret leading hyphens in variable values as command flags.
**Prevention:** Use `set -f` and `set +f` around `set -- $variable` to disable glob expansion during word-splitting. Replace `echo "$variable"` with `printf '%s\n' "$variable"` to ensure the string is treated literally and not as an option.

## 2029-05-15 - [High] Incomplete Hardening of Secondary Scripts
**Vulnerability:** While core scripts like `clone-repos.sh` were hardened against argument injection and path traversal, secondary utility scripts like `add-branch.sh` were missing similar protections (specifically `git check-ref-format` validation and `--` separators), creating weak points in the system.
**Learning:** Security hardening must be applied comprehensively across all entry points that handle user-provided strings. Utility scripts that modify the repository or filesystem are just as critical as primary tools.
**Prevention:** Maintain a checklist of standard shell hardening patterns (validation, separators, safe output) and ensure every script that handles external input adheres to them. Use `git check-ref-format --allow-onelevel` consistently for all branch name inputs.

## 2029-05-16 - [Medium] Insufficient Branch Name Validation and Argument Injection in grep
**Vulnerability:** Branch names from `repos.list` were not consistently validated with `git check-ref-format`, and leading hyphens were not explicitly blocked, allowing for malformed path creation or potential argument injection. Additionally, `grep` was used without `-F` or `-e` when searching for branch names in `git worktree list` output, making it vulnerable to pattern injection.
**Learning:** `git check-ref-format --allow-onelevel` is excellent for validating branch name structure but does not always reject leading hyphens (which can be interpreted as flags by other commands). Explicitly blocking hyphens at the start of branch names is a necessary additional layer of defense.
**Prevention:** Always combine `git check-ref-format --allow-onelevel` with a check for leading hyphens (`[[ "$branch" == -* ]]`). Use `grep -F -e` when searching for literal strings that may contain user-provided data.

## 2029-05-17 - [Medium] Regression Risk with set -u in Hardened Shell Scripts
**Vulnerability:** Applying `set -u` (nounset) for security hardening can cause scripts to crash if variables are used in conditional checks or case statements before being explicitly initialized.
**Learning:** While `set -u` is a valuable security measure to prevent issues with uninitialized variables, it requires proactive initialization of all variables that may be evaluated, even if they start as empty.
**Prevention:** Ensure all variables (e.g., `BRANCH_NAME`, `TARGET_DIR`, `USE_BRANCH`) are initialized to safe default values at the beginning of the script before any logic or argument parsing that might evaluate them.

## 2025-05-24 - [High] Path Traversal in Planning Phase of Repository Management
**Vulnerability:** `scripts/helper/clone-repos.sh` implemented a "planning phase" to pre-calculate repository names and locations but failed to validate user-provided target directories in this phase. An attacker could provide a malicious target directory that would be rejected in the execution phase but remained in the "plan", allowing a subsequent worktree or branch clone to use that unvalidated path as its base directory.
**Learning:** Security validation must be applied at every stage where user-controlled data is processed, especially if that data is stored and reused later. Validating only at the point of final use (execution) can be bypassed if earlier stages (planning/parsing) lack consistent checks.
**Prevention:** Ensure that all user-provided path components are validated immediately upon parsing, regardless of whether they are used immediately or stored for future reference. Apply the same strict `/*|*..*` validation rules consistently across all phases of a script.
## 2025-05-25 - [High] Insufficient Path Validation for Workspace Folders
**Vulnerability:** `run-pipeline.sh` and `install-r-deps.sh` used a `case` statement `/*|*../*..*` and `../*` to validate workspace folder paths. This failed to catch exact `..` or trailing `..` (e.g., `repo/..`), allowing path traversal.
**Learning:** Glob patterns like `*../*..*` only catch multiple occurrences of `..` separated by a slash, and `../*` only catches `..` at the beginning followed by a slash. They do not cover all permutations of directory traversal.
**Prevention:** Use a more comprehensive `case` pattern like `/*|..|*/..|../*|*/../*` to catch `..` in any position. If certain traversals are allowed (like a single level up for sibling repos), use explicit logic to validate that the path matches exactly the allowed pattern and nothing more.

## 2025-06-14 - [Medium] Credential Leakage in Normalized Git URLs
**Vulnerability:** Embedded credentials (e.g., `https://token@github.com/...`) in Git URLs were preserved during normalization in `normalise_remote_to_https`, leading to potential leakage in logs and workspace configuration files.
**Learning:** Normalizing URLs for display or configuration must explicitly strip sensitive user information. Relying on Git to handle credentials internally is safer than passing them around in URL strings.
**Prevention:** Use `sed` or similar tools to strip the `user:pass@` or `token@` part from HTTPS URLs before using them in any context that might be logged or stored in configuration files.

## 2029-05-18 - [Medium] Unintended Glob Expansion and Argument Injection in Codespaces Auth Helper
**Vulnerability:** `scripts/helper/codespaces-auth-add.sh` was vulnerable to unintended glob expansion when processing repository overrides via the `-r` flag. Additionally, it lacked `--` separators in `mv`, `jq`, and `python` commands, making it susceptible to argument injection from filenames starting with a hyphen.
**Learning:** Even in helper scripts, unquoted variable expansion during word-splitting or loop iteration can lead to globbing if not explicitly disabled. Furthermore, any command that accepts filenames must use the `--` separator to prevent those filenames from being interpreted as options.
**Prevention:** Use `set -f` and `set +f` around loops that iterate over word-split variables. Always use the `--` separator before positional arguments in commands like `mv`, `jq`, `rm`, etc. When invoking Python with stdin (`-`), ensure the argument index for the filename correctly matches the script's expectations (usually `sys.argv[1]`).

## 2025-05-26 - [High] Path Traversal and Fragile Regex in Codespaces Helper
**Vulnerability:** The `-d/--devcontainer` argument in `codespaces-auth-add.sh` allowed arbitrary paths (absolute or `..`), enabling overwriting of system files. Additionally, a regex intended to strip JSONC comments (`//`) incorrectly matched `//` inside URLs (e.g. `https://`), corrupting data.
**Learning:** Argument parsing for file paths must always be hardened with validation logic, even in internal helpers. Heuristic-based parsing (like regex for JSONC) is dangerous and must account for common edge cases like protocol prefixes in URLs.
**Prevention:** Always validate user-provided paths for `-d` arguments using a strict check against `/*|*..*`. Use negative lookbehind in regex (e.g. `(?<!:)\/\/`) to avoid matching protocol separators when stripping comments.

## 2025-06-10 - [Medium] Pervasive Missing Nounset and Option Terminators in Shell Tooling
**Vulnerability:** Multiple secondary and helper scripts (e.g., `run-pipeline.sh`, `update-scripts.sh`) were missing `set -u` (nounset) and the `--` option terminator for common commands like `basename` and `git add`.
**Learning:** While core scripts were hardened, utility scripts often trailed behind in security standards. `basename` is particularly susceptible to argument injection if a path component starts with a hyphen.
**Prevention:** Enforce `set -u` across all scripts to catch uninitialized variables. Consistently use the `--` separator for *all* commands that accept variable-based positional arguments, including standard utilities like `basename`, `dirname`, and `git add`.

## 2025-06-11 - [Improvement] Non-Interactive Git Hardening and Robust JSON Processing
**Pattern:** Core scripts lacked explicit hardening for non-interactive Git use, potentially leading to hangs in automated environments (like CI/CD) when credentials were requested. Additionally, large JSON processing used shell variable expansion, risking "Argument list too long" errors.
**Learning:** Automated scripts must explicitly disable terminal prompts for Git and SSH to ensure they fail fast rather than hanging. Relying on shell variable expansion for large configuration files is fragile.
**Prevention:** Export `GIT_TERMINAL_PROMPT=0` and `GIT_ASKPASS=/bin/false` in all scripts using Git. Use a `git` wrapper function that redirects `/dev/null` to stdin. For JSON processing, have tools read directly from file paths instead of using intermediate shell variables.

## 2025-06-12 - [High] CRLF Injection in HTTP Headers and Non-Portable mktemp Usage
**Vulnerability:** GitHub credentials (`GH_USER` and `GH_TOKEN`) extracted from `git credential fill` lacked full newline sanitization, potentially allowing CRLF injection in subsequent `curl` calls. Additionally, the use of `mktemp --` (option terminator) broke portability on BSD-based systems (like macOS).
**Learning:** Shell command substitution `$(...)` strips trailing newlines, but internal ones or carriage returns can persist. Explicit sanitization is necessary for variables used in HTTP headers. While `--` is a security best practice for many tools to prevent argument injection, it is not universally supported by all implementations of `mktemp`.
**Prevention:** Use `tr -d '\r\n'` to sanitize all components of a credential or any variable destined for an HTTP header. For `mktemp`, prioritize portability by omitting `--` if the template is the final argument and unlikely to be confused with an option.

## 2025-06-13 - [Medium] Fragile Test Isolation and Silent Failures in Core Scripts
**Vulnerability:** Core cloner script used `trap '' ERR`, which suppressed non-zero exit codes from failed Git operations, leading to silent failures. Integration tests were vulnerable to `SIGPIPE` when piping long-running scripts into `grep -q`. Host-level Git credentials could also leak into test environments, causing false passes.
**Learning:** Error suppression with `trap` is dangerous in security-critical scripts as it masks failures in validation or authentication. Automated tests must be strictly isolated from the host's environment (e.g. `HOME`, `GIT_CONFIG_NOSYSTEM`) to ensure they truly verify the script's logic.
**Prevention:** Avoid `trap '' ERR`. Capture script output to variables before processing with `grep` to avoid `SIGPIPE`. Use temporary `HOME` directories and `GIT_CONFIG_NOSYSTEM=1` for all tests involving Git authentication or configuration.

## 2025-07-15 - [High] Insecure Credential Parsing and Header Injection
**Vulnerability:** `get_credentials` used `awk -F=` to parse `git credential fill` output, which truncated tokens containing equals signs. It also lacked CRLF sanitization for `GH_USER` and `GH_TOKEN` environment variables.
**Learning:** Using a single character delimiter like `=` for parsing key-value pairs is fragile if the value itself can contain that delimiter. GitHub tokens frequently contain `=` characters. Lack of sanitization of user-provided environment variables in scripts that interact with web APIs can lead to header injection vulnerabilities.
**Prevention:** Use `sed -n 's/^key=//p'` for robust extraction of values from key-value pairs. Always sanitize external inputs (including environment variables) with `tr -d '\r\n'` before using them in HTTP headers or security-sensitive contexts.

## 2025-08-20 - [Improvement] Reusable URL Encoding Pattern for API Interactions
**Vulnerability:** GitHub API components (owner, repo, branch) were interpolated directly into URL strings without encoding. While primary validation regexes restricted most characters, branch names (validated only by `git check-ref-format`) could contain characters like `/` or `#` that would break URL structure or lead to path manipulation.
**Learning:** Even with input validation, parameters destined for URL paths must be explicitly encoded to ensure they are treated as literal data by the receiving API and to prevent misinterpretation of URL metacharacters.
**Prevention:** Implement a reusable `urlencode` helper using `jq -rR '@uri'` (available in the project's environment) and apply it to all user-controlled or external data interpolated into URL strings.

## 2026-04-22 - [Medium] Consistent Hyphen Blocking and Robust Option Parsing
**Vulnerability:** User-provided target directory names and repository specifications were validated for path traversal but not for leading hyphens. This allowed for potential argument injection if these strings were passed to Git or other shell commands without the `--` separator.
**Learning:** Hardening against argument injection requires two layers: (1) strict input validation to block metacharacters and leading hyphens, and (2) consistent use of the `--` option terminator in all command invocations. Encountering "Warning" instead of "Error" for unknown options in parsers can also mask injection attempts.
**Prevention:** Always include `-*` in path and identifier validation `case` statements. Upgrade unknown option warnings to errors to "fail securely". Consistently apply `--` before any variable-based positional argument in Git, curl, awk, and other standard utilities.
