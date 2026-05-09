# Version of the bundled bash scripts inside this package.
# Updated automatically by the version-and-release workflow.
.bundled_cli_version <- "1.3.9"

#' Return the version of the bundled bash scripts in this package
#'
#' The R package ships a copy of some Bash helper scripts (e.g., for
#' \code{repos_workspace()}).  This function returns the version string of
#' those bundled scripts.  Primary functionality (clone, run, etc.) uses the
#' installed \code{repos} Go binary instead; see
#' \code{\link{repos_installed_cli_version}} and
#' \code{\link{repos_install_cli}}.
#'
#' @return A character string with the bundled script version (e.g. \code{"1.3.9"}).
#'
#' @examples
#' repos_bundled_cli_version()
#'
#' @export
repos_bundled_cli_version <- function() {
  .bundled_cli_version
}

#' Return the version of the repos CLI installed on the system PATH
#'
#' Runs \code{repos --version} using the system-wide \code{repos} binary.  If
#' no system-wide \code{repos} CLI is found, returns \code{NULL} instead of
#' raising an error.
#'
#' @return A character string with the installed CLI version, or \code{NULL}
#'   if \code{repos} is not found on the system \code{PATH}.
#'
#' @examples
#' \dontrun{
#' ver <- repos_installed_cli_version()
#' if (is.null(ver)) {
#'   message("repos CLI is not installed on this system.")
#' } else {
#'   message("Installed CLI version: ", ver)
#' }
#' }
#'
#' @export
repos_installed_cli_version <- function() {
  # Check whether `repos` is on PATH
  found <- nchar(Sys.which("repos")) > 0L
  if (!found) {
    return(NULL)
  }
  out <- tryCatch(
    system2("repos", "--version", stdout = TRUE, stderr = TRUE),
    error = function(e) NULL
  )
  if (is.null(out) || length(out) == 0L) {
    return(NULL)
  }
  # Strip a leading "v" if present (e.g. "v1.1.0" -> "1.1.0")
  sub("^v", "", trimws(out[[1L]]))
}

#' Install the repos CLI
#'
#' Prints OS-appropriate instructions for installing the \code{repos}
#' Go binary and, when \code{run = TRUE}, attempts to run the installer
#' automatically.
#'
#' @details
#' Most R functions in this package (\code{repos_clone()}, \code{repos_run()},
#' etc.) call the \code{repos} Go binary directly.  The binary must be on
#' your \code{PATH} for those functions to work.  Use this function to install
#' it.
#'
#' When \code{run = TRUE}, the function downloads the prebuilt Go binary from
#' the latest GitHub release on Linux (via \code{install-local.sh}) or uses
#' Homebrew on macOS.  On Windows, only instructions are printed.
#'
#' @param run Logical (default \code{FALSE}).  If \code{TRUE}, attempt to run
#'   the installer automatically.
#'
#' @return Invisibly returns \code{NULL}.
#'
#' @examples
#' \dontrun{
#' # Print installation instructions for your OS
#' repos_install_cli()
#'
#' # Print instructions AND run the installer
#' repos_install_cli(run = TRUE)
#' }
#'
#' @export
repos_install_cli <- function(run = FALSE) {
  sysname <- Sys.info()[["sysname"]]

  if (sysname == "Linux") {
    message("To install the repos CLI on Ubuntu/Debian, choose one of:\n")
    message("  # Option 1: APT repository (recommended -- keeps repos up to date):")
    message("  curl -fsSL https://raw.githubusercontent.com/MiguelRodo/apt-miguelrodo/main/KEY.gpg \\")
    message("     | sudo gpg --dearmor -o /usr/share/keyrings/miguelrodo-repos.gpg")
    message('  echo "deb [signed-by=/usr/share/keyrings/miguelrodo-repos.gpg] https://raw.githubusercontent.com/MiguelRodo/apt-miguelrodo/main/ ./" \\')
    message("     | sudo tee /etc/apt/sources.list.d/miguelrodo-repos.list >/dev/null")
    message("  sudo apt-get update && sudo apt-get install -y repos\n")
    message("  # Option 2: User-level install (no sudo required):")
    message("  git clone https://github.com/MiguelRodo/repos.git /tmp/repos-cli")
    message("  bash /tmp/repos-cli/install-local.sh\n")
    if (isTRUE(run)) {
      message("Running user-level installer...")
      tmp <- file.path(tempdir(), "repos-cli")
      ret <- system(paste0("git clone https://github.com/MiguelRodo/repos.git ", shQuote(tmp),
                           " && bash ", shQuote(file.path(tmp, "install-local.sh"))))
      if (ret != 0L) {
        warning("Installer exited with status ", ret,
                ". Check the output above for details.")
      }
    }
  } else if (sysname == "Darwin") {
    message("To install the repos CLI on macOS, run:\n")
    message("  brew tap MiguelRodo/repos")
    message("  brew install repos\n")
    if (isTRUE(run)) {
      message("Running Homebrew installer...")
      ret <- system("brew tap MiguelRodo/repos && brew install repos")
      if (ret != 0L) {
        warning("Installer exited with status ", ret,
                ". Check the output above for details.")
      }
    }
  } else if (sysname == "Windows") {
    message("To install the repos CLI on Windows, run in PowerShell:\n")
    message("  scoop bucket add repos https://github.com/MiguelRodo/scoop-bucket")
    message("  scoop install repos\n")
    message("Or download and run install.ps1 from the releases page:")
    message("  https://github.com/MiguelRodo/repos/releases\n")
    message("(Automatic installation via run = TRUE is not supported on Windows.)")
  } else {
    message("To install the repos CLI, see the installation guide:")
    message("  https://miguelrodo.github.io/repos/install.html\n")
  }

  invisible(NULL)
}


#' Run the repos Go binary
#'
#' Internal helper that locates the \code{repos} binary on PATH and invokes
#' it with the given subcommand and arguments via \code{system2()}.
#'
#' @param subcommand Character string.  The repos subcommand to run (e.g.
#'   \code{"clone"}, \code{"run"}, \code{"add-branch"}).
#' @param args Character vector of arguments to pass after the subcommand.
#' @return Invisibly returns the exit status of the binary (0 for success).
#' @keywords internal
run_repos_binary <- function(subcommand, args = character()) {
  binary <- Sys.which("repos")
  if (nchar(binary) == 0L) {
    stop(
      "The 'repos' binary was not found on PATH.\n",
      "Install it with: repos_install_cli(run = TRUE)\n",
      "or follow the guide at: https://miguelrodo.github.io/repos/install.html"
    )
  }
  exit_status <- system2(binary, args = c(subcommand, args))
  invisible(exit_status)
}

#' Run a bundled repos script
#'
#' Internal helper that locates a bundled script and executes it via
#' \code{system2()}.  Retained for commands whose Go binary interface differs
#' from the original bash script (e.g., \code{repos_workspace()}).
#'
#' @param script_name Name of the script file inside \code{inst/scripts/}.
#' @param args Character vector of arguments to pass to the script.
#' @return Invisibly returns the exit status of the script (0 for success).
#' @keywords internal
run_repos_script <- function(script_name, args = character()) {
  script_path <- system.file(file.path("scripts", script_name), package = "repos")

  if (script_path == "" || !file.exists(script_path)) {
    stop(
      "Cannot find ", script_name,
      " script. Make sure the package is properly installed."
    )
  }

  exit_status <- system2(script_path, args = args)
  invisible(exit_status)
}

#' Multi-Repository Management Tool
#'
#' Dispatches to the appropriate repos subcommand.
#'
#' @param command Character string specifying the subcommand to run.
#'   Must be one of \code{"clone"}, \code{"workspace"}, \code{"codespace"},
#'   \code{"codespaces"}, \code{"run"}, \code{"add_branch"},
#'   \code{"update_branches"}, or \code{"update_scripts"}.
#' @param ... Additional arguments passed to the underlying function.
#'
#' @return Invisibly returns the exit status of the command (0 for success).
#'
#' @details
#' Most subcommands delegate to the \code{repos} Go binary.  Install it with
#' \code{\link{repos_install_cli}(run = TRUE)} if not already on your PATH.
#'
#' \code{repos("clone", ...)} calls \code{\link{repos_clone}}.
#'
#' \code{repos("workspace", ...)} calls \code{\link{repos_workspace}} (uses
#' the bundled bash script).
#'
#' \code{repos("codespace", ...)} / \code{repos("codespaces", ...)} calls
#' \code{\link{repos_codespace}}.
#'
#' \code{repos("run", ...)} calls \code{\link{repos_run}}.
#'
#' \code{repos("add_branch", ...)} calls \code{\link{repos_add_branch}}.
#'
#' \code{repos("update_branches", ...)} calls \code{\link{repos_update_branches}}.
#'
#' \code{repos("update_scripts", ...)} calls \code{\link{repos_update_scripts}}.
#'
#' @examples
#' \dontrun{
#' repos("clone")
#' repos("workspace")
#' repos("codespace")
#' repos("run", "bash", "run.sh")
#' repos("add_branch", "data-tidy")
#' repos("update_branches")
#' repos("update_scripts")
#' }
#'
#' @export
repos <- function(command, ...) {
  valid <- c("clone", "workspace", "codespace", "codespaces", "run",
             "add_branch", "update_branches", "update_scripts")
  if (missing(command) || !(command %in% valid)) {
    message("Usage: repos(command, ...)\n")
    message("Commands:")
    message("  \"clone\"           Clone repositories listed in repos.list")
    message("  \"workspace\"       Generate or update the VS Code workspace file")
    message("  \"codespace\"       Configure GitHub Codespaces authentication")
    message("  \"run\"             Execute a command inside each cloned repository")
    message("  \"add_branch\"      Create a new worktree/branch off the current repo")
    message("  \"update_branches\" Fetch and fast-forward all repos in the workspace")
    message("  \"update_scripts\"  Mirror scripts and workflows to managed repositories")
    message("\nSee ?repos_clone, ?repos_workspace, ?repos_codespace, ?repos_run,")
    message("?repos_add_branch, ?repos_update_branches,")
    message("and ?repos_update_scripts for details.")
    return(invisible(1L))
  }

  switch(command,
    clone           = repos_clone(...),
    workspace       = repos_workspace(...),
    codespace       = repos_codespace(...),
    codespaces      = repos_codespace(...),
    run             = repos_run(...),
    add_branch      = repos_add_branch(...),
    update_branches = repos_update_branches(...),
    update_scripts  = repos_update_scripts(...)
  )
}

#' Clone Repositories Listed in repos.list
#'
#' Clone all repositories (and branches) described in a \code{repos.list} file
#' into the parent directory of the current working directory.
#'
#' @param file Path to repos list file (default: \code{repos.list}, falling
#'   back to \code{repos-to-clone.list} if absent).
#' @param worktree Logical. If \code{TRUE}, pass \code{--worktree} globally so
#'   that every \code{@branch} line creates a Git worktree instead of a fresh
#'   clone.
#' @param fetch_mode Character. Controls fetch refspec behaviour after cloning.
#'   One of:
#'   \itemize{
#'     \item \code{"deferred"} (default) — fast \code{--single-branch} clone,
#'       then the wildcard fetch refspec is immediately restored so normal
#'       multi-branch commands work after a subsequent \code{git fetch}.
#'     \item \code{"single"} — keep the restricted single-branch refspec for
#'       maximum isolation; best for CI/CD, monorepos, or metered connections.
#'     \item \code{"all"} — full clone without \code{--single-branch}; all
#'       remote branches are downloaded upfront.
#'   }
#' @param debug Logical. If \code{TRUE}, enable debug tracing to stderr.
#' @param debug_file Ignored (retained for backward compatibility).
#' @param ... Additional arguments passed directly to \code{repos clone}.
#'
#' @return Invisibly returns the exit status of the binary (0 for success).
#'
#' @details
#' This function calls \code{repos clone} from the \code{repos} Go binary.
#' The binary must be on your \code{PATH}; install it with
#' \code{\link{repos_install_cli}(run = TRUE)} if needed.
#'
#' Each non-empty, non-comment line in the repos list file describes one of
#' three operations:
#' \enumerate{
#'   \item Clone a repository (default or all branches): \code{owner/repo}
#'   \item Clone a specific branch: \code{owner/repo@branch}
#'   \item Clone or create a worktree for a branch from the fallback repo:
#'     \code{@branch}
#' }
#' Repositories are always cloned into the \strong{parent} directory of the
#' current working directory (i.e. the directory containing the project that
#' holds \code{repos.list}).
#'
#' @examples
#' \dontrun{
#' # Clone from the default repos.list
#' repos_clone()
#'
#' # Use a different list file
#' repos_clone(file = "my-repos.list")
#'
#' # Use worktrees globally for all @branch lines
#' repos_clone(worktree = TRUE)
#'
#' # CI/CD: strict single-branch isolation
#' repos_clone(fetch_mode = "single")
#'
#' # Download all branches upfront
#' repos_clone(fetch_mode = "all")
#' }
#'
#' @export
repos_clone <- function(file = NULL, worktree = FALSE, debug = FALSE,
                        debug_file = NULL, fetch_mode = NULL, ...) {
  args <- character()

  # Backward compatibility for positional calls introduced while fetch_mode
  # was temporarily the 3rd argument.
  # TODO: remove this shim in the next major release.
  # repos_clone(file, worktree, "single")
  if (is.null(fetch_mode) && is.character(debug) && length(debug) == 1 &&
      debug %in% c("deferred", "single", "all")) {
    fetch_mode <- debug
    debug <- FALSE
  }

  if (!is.null(file)) {
    args <- c(args, "--file", file)
  }

  if (isTRUE(worktree)) {
    args <- c(args, "--worktree")
  }

  if (!is.null(fetch_mode)) {
    valid_fetch_modes <- c(
      "deferred" = "--fetch-all-deferred",
      "single"   = "--fetch-single",
      "all"      = "--fetch-all"
    )
    if (!fetch_mode %in% names(valid_fetch_modes)) {
      stop(sprintf(
        "'fetch_mode' must be \"deferred\", \"single\", or \"all\"; got: %s",
        dQuote(fetch_mode)
      ))
    }
    args <- c(args, valid_fetch_modes[[fetch_mode]])
  }

  if (isTRUE(debug)) {
    args <- c(args, "--debug")
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_binary("clone", args)
}

#' Generate VS Code Workspace File
#'
#' Generate or update the VS Code multi-root workspace file from a
#' \code{repos.list} file.
#'
#' @param file Path to repos list file (default: repos.list)
#' @param debug Logical. If \code{TRUE}, enable debug output to stderr
#' @param debug_file Character string or logical. Enable debug output to file
#'   (auto-generated if \code{TRUE})
#' @param ... Additional arguments passed directly to the bundled
#'   \code{vscode-workspace-add.sh} script as-is.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' This function uses the bundled \code{vscode-workspace-add.sh} Bash script.
#' It writes (or refreshes) the \code{entire-project.code-workspace} file in
#' your project directory so you can open all cloned repositories as a
#' multi-root workspace in VS Code or other IDEs that support the VS Code
#' workspace format.
#'
#' @examples
#' \dontrun{
#' # Generate workspace from default repos.list
#' repos_workspace()
#'
#' # Use a different file
#' repos_workspace(file = "my-repos.list")
#' }
#'
#' @export
repos_workspace <- function(file = NULL, debug = FALSE, debug_file = NULL, ...) {
  args <- character()

  if (!is.null(file)) {
    args <- c(args, "-f", file)
  }

  if (isTRUE(debug)) {
    args <- c(args, "--debug")
  }

  if (!is.null(debug_file)) {
    if (isTRUE(debug_file)) {
      args <- c(args, "--debug-file")
    } else {
      args <- c(args, "--debug-file", debug_file)
    }
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_script("helper/vscode-workspace-add.sh", args = args)
}

#' Configure GitHub Codespaces Authentication
#'
#' Set the \code{GH_TOKEN} Codespaces secret for every repository listed in
#' \code{repos.list}.
#'
#' @param file Path to repos list file (default: \code{repos.list}, falling
#'   back to \code{repos-to-clone.list} if absent).
#' @param ... Additional arguments passed directly to \code{repos codespaces-auth}.
#'
#' @return Invisibly returns the exit status of the binary (0 for success).
#'
#' @details
#' This function calls \code{repos codespaces-auth} from the \code{repos} Go
#' binary.  The binary must be on your \code{PATH}; install it with
#' \code{\link{repos_install_cli}(run = TRUE)} if needed.
#'
#' The \code{gh} CLI must also be authenticated (\code{gh auth login}) before
#' running this command.
#'
#' @examples
#' \dontrun{
#' # Configure Codespaces for all repos in repos.list
#' repos_codespace()
#'
#' # Use a different list file
#' repos_codespace(file = "my-repos.list")
#' }
#'
#' @export
repos_codespace <- function(file = NULL, ...) {
  args <- character()

  if (!is.null(file)) {
    args <- c(args, "--file", file)
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_binary("codespaces-auth", args)
}

#' Run a Command Across Repositories
#'
#' Execute a shell command inside each cloned repository.
#'
#' @param file Path to repos list file (default: \code{repos.list}, falling
#'   back to \code{repos-to-clone.list} if absent).
#' @param concurrent Logical. If \code{TRUE}, run the command in all
#'   repositories concurrently instead of sequentially.
#' @param ... The command and its arguments to run in each repository (passed
#'   as positional arguments after any flags).  For example,
#'   \code{repos_run("bash", "build.sh")} or
#'   \code{repos_run("make", "test")}.
#'
#' @return Invisibly returns the exit status of the binary (0 for success).
#'
#' @details
#' This function calls \code{repos run} from the \code{repos} Go binary.
#' The binary must be on your \code{PATH}; install it with
#' \code{\link{repos_install_cli}(run = TRUE)} if needed.
#'
#' The command is run inside each repository directory that appears in the
#' repos list file.  If any repository's command exits with a non-zero status,
#' the overall exit status is non-zero.
#'
#' @examples
#' \dontrun{
#' # Run a bash script in each repo
#' repos_run("bash", "run.sh")
#'
#' # Run make in each repo
#' repos_run("make", "test")
#'
#' # Run concurrently
#' repos_run("bash", "build.sh", concurrent = TRUE)
#'
#' # Use a different repos list file
#' repos_run("bash", "run.sh", file = "my-repos.list")
#' }
#'
#' @export
repos_run <- function(file = NULL, concurrent = FALSE, ...) {
  args <- character()

  if (!is.null(file)) {
    args <- c(args, "--file", file)
  }

  if (isTRUE(concurrent)) {
    args <- c(args, "--concurrent")
  }

  cmd_args <- c(...)
  if (length(cmd_args) == 0L) {
    stop("A command to run must be provided via `...` (e.g. repos_run(\"bash\", \"run.sh\"))")
  }

  run_repos_binary("run", c(args, cmd_args))
}

#' Create a New Worktree/Branch
#'
#' Create a new Git worktree (or branch) from the current repository, push it
#' to origin, and update \code{repos.list} and the VS Code workspace file.
#'
#' @param branch_name Character string. Name of the new branch to create.
#' @param target_dir Character string. Optional custom directory name
#'   (default: \code{<repo>-<branch>}).
#' @param use_branch Logical. If \code{TRUE}, create as a regular branch
#'   instead of a worktree.
#' @param ... Additional arguments passed directly to \code{repos add-branch}.
#'
#' @return Invisibly returns the exit status of the binary (0 for success).
#'
#' @details
#' This function calls \code{repos add-branch} from the \code{repos} Go
#' binary.  The binary must be on your \code{PATH}; install it with
#' \code{\link{repos_install_cli}(run = TRUE)} if needed.
#'
#' @examples
#' \dontrun{
#' repos_add_branch("data-tidy")
#' repos_add_branch("analysis", target_dir = "my-analysis")
#' repos_add_branch("paper", use_branch = TRUE)
#' }
#'
#' @export
repos_add_branch <- function(branch_name, target_dir = NULL, use_branch = FALSE, ...) {
  args <- branch_name

  if (!is.null(target_dir)) {
    args <- c(args, target_dir)
  }

  if (isTRUE(use_branch)) {
    args <- c(args, "--branch")
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_binary("add-branch", args)
}

#' Fetch and Fast-Forward All Repositories
#'
#' Fetch from remote and fast-forward the current branch in every Git
#' repository found in the workspace parent directory.
#'
#' @param dir Character string. Base directory to scan for repositories
#'   (default: parent of the current working directory).
#' @param jobs Integer. Maximum number of concurrent git operations
#'   (default: number of CPU cores).
#' @param ... Additional arguments passed directly to \code{repos update-branches}.
#'
#' @return Invisibly returns the exit status of the binary (0 for success).
#'
#' @details
#' This function calls \code{repos update-branches} from the \code{repos} Go
#' binary.  The binary must be on your \code{PATH}; install it with
#' \code{\link{repos_install_cli}(run = TRUE)} if needed.
#'
#' Repositories with uncommitted changes are skipped.  Repositories whose
#' current branch does not track a remote branch are also skipped.
#'
#' @examples
#' \dontrun{
#' repos_update_branches()
#' repos_update_branches(jobs = 4L)
#' }
#'
#' @export
repos_update_branches <- function(dir = NULL, jobs = NULL, ...) {
  args <- character()

  if (!is.null(dir)) {
    args <- c(args, "--dir", dir)
  }

  if (!is.null(jobs)) {
    args <- c(args, "--jobs", as.character(jobs))
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_binary("update-branches", args)
}

#' Mirror Scripts and Workflows to Managed Repositories
#'
#' Copy the \code{.github/workflows} and \code{scripts} directories from the
#' current repository into each repository listed in \code{repos.list}.
#'
#' @param file Path to repos list file (default: \code{repos.list}, falling
#'   back to \code{repos-to-clone.list} if absent).
#' @param dry_run Logical. If \code{TRUE}, show what would be updated without
#'   making changes.
#' @param stage Logical. If \code{TRUE}, stage synced paths with
#'   \code{git add} after copying.
#' @param ... Additional arguments passed directly to \code{repos update-scripts}.
#'
#' @return Invisibly returns the exit status of the binary (0 for success).
#'
#' @details
#' This function calls \code{repos update-scripts} from the \code{repos} Go
#' binary.  The binary must be on your \code{PATH}; install it with
#' \code{\link{repos_install_cli}(run = TRUE)} if needed.
#'
#' @examples
#' \dontrun{
#' repos_update_scripts()
#' repos_update_scripts(dry_run = TRUE)
#' repos_update_scripts(stage = TRUE)
#' }
#'
#' @export
repos_update_scripts <- function(file = NULL, dry_run = FALSE, stage = FALSE, ...) {
  args <- character()

  if (!is.null(file)) {
    args <- c(args, "--file", file)
  }

  if (isTRUE(dry_run)) {
    args <- c(args, "--dry-run")
  }

  if (isTRUE(stage)) {
    args <- c(args, "--stage")
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_binary("update-scripts", args)
}
