# Version of the repos CLI bundled inside this package.
# Updated automatically by the version-and-release workflow.
.bundled_cli_version <- "1.3.1"

#' Return the version of the repos CLI bundled in this package
#'
#' The R package ships its own copy of the Bash scripts at a specific CLI
#' version.  This function returns that pinned version string.
#'
#' @return A character string with the bundled CLI version (e.g. \code{"1.1.0"}).
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
#' Prints OS-appropriate instructions for installing the \code{repos} command-line
#' tool and, when \code{run = TRUE}, attempts to run the installer automatically.
#'
#' @details
#' The \code{repos} R package bundles all required Bash scripts, so functions
#' such as \code{repos_run()} work without the \code{repos} CLI being on your
#' \code{PATH}.  However, if you also want to invoke \code{repos} from a
#' terminal, you need to install the CLI separately.
#'
#' When \code{run = TRUE}, the function runs the user-level installer
#' (\code{install-local.sh}) on Linux or the \code{brew} installer on macOS.
#' On Windows, only instructions are printed.
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


#' Run a repos script
#'
#' Internal helper that locates a bundled script and executes it via
#' \code{system2()}.
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
#' @param ... Additional arguments passed to the underlying script.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' \code{repos("clone", ...)} delegates to \code{clone-repos.sh} (see
#' \code{\link{repos_clone}}).
#'
#' \code{repos("workspace", ...)} delegates to \code{vscode-workspace-add.sh} (see
#' \code{\link{repos_workspace}}).
#'
#' \code{repos("codespace", ...)} / \code{repos("codespaces", ...)} delegates to
#' \code{codespaces-auth-add.sh} (see \code{\link{repos_codespace}}).
#'
#' \code{repos("run", ...)} delegates to \code{run-pipeline.sh} (see
#' \code{\link{repos_run}}).
#'
#' \code{repos("add_branch", ...)} delegates to \code{add-branch.sh} (see
#' \code{\link{repos_add_branch}}).
#'
#' \code{repos("update_branches", ...)} delegates to \code{update-branches.sh} (see
#' \code{\link{repos_update_branches}}).
#'
#' \code{repos("update_scripts", ...)} delegates to \code{update-scripts.sh} (see
#' \code{\link{repos_update_scripts}}).
#'
#' @examples
#' \dontrun{
#' repos("clone")
#' repos("workspace")
#' repos("codespace")
#' repos("run")
#' repos("run", script = "build.sh")
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
    message("  \"run\"             Execute a script inside each cloned repository")
    message("  \"add_branch\"      Create a new worktree/branch off the current repo")
    message("  \"update_branches\" Update all worktrees with the latest devcontainer config")
    message("  \"update_scripts\"  Update scripts from the upstream CompTemplate repository")
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
#' @param debug Logical. If \code{TRUE}, enable debug tracing to stderr.
#' @param debug_file Character string or logical. Enable debug tracing to a
#'   file.  If \code{TRUE}, an auto-generated filename is used; if a non-empty
#'   string, that path is used as the log file.
#' @param ... Additional arguments passed directly to the
#'   \code{clone-repos.sh} script as-is.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' This function is a wrapper around \code{clone-repos.sh}.  Each non-empty,
#' non-comment line in the repos list file describes one of three operations:
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
#' }
#'
#' @export
repos_clone <- function(file = NULL, worktree = FALSE, debug = FALSE,
                        debug_file = NULL, ...) {
  args <- character()

  if (!is.null(file)) {
    args <- c(args, "-f", file)
  }

  if (isTRUE(worktree)) {
    args <- c(args, "--worktree")
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

  run_repos_script("helper/clone-repos.sh", args = args)
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
#' @param ... Additional arguments passed directly to the
#'   \code{vscode-workspace-add.sh} script as-is.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' This function is a wrapper around \code{vscode-workspace-add.sh}.
#' It writes (or refreshes) the \code{entire-project.code-workspace} file in
#' your project directory so you can open all cloned repositories as a
#' multi-root workspace in VS Code or other IDEs that support the VS Code workspace format.
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
#' Inject the \code{GH_TOKEN} Codespaces secret into every cloned repository
#' that has a \code{devcontainer.json}.
#'
#' @param file Path to repos list file (default: repos.list)
#' @param devcontainer Character vector of paths to devcontainer.json files
#' @param permissions Character string. \code{"all"} or \code{"contents"}
#' @param tool Character string. Force tool for authentication helper
#'   (e.g., \code{"jq"}, \code{"python"})
#' @param debug Logical. If \code{TRUE}, enable debug output to stderr
#' @param debug_file Character string or logical. Enable debug output to file
#'   (auto-generated if \code{TRUE})
#' @param ... Additional arguments passed directly to the
#'   \code{codespaces-auth-add.sh} script as-is.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' This function is a wrapper around \code{codespaces-auth-add.sh}.
#'
#' @examples
#' \dontrun{
#' # Configure Codespaces with default devcontainer path
#' repos_codespace()
#'
#' # Specify devcontainer paths
#' repos_codespace(devcontainer = ".devcontainer/devcontainer.json")
#'
#' # Multiple devcontainer paths
#' repos_codespace(devcontainer = c("path1/devcontainer.json",
#'                                  "path2/devcontainer.json"))
#' }
#'
#' @export
repos_codespace <- function(file = NULL, devcontainer = NULL, permissions = NULL,
                            tool = NULL, debug = FALSE, debug_file = NULL, ...) {
  args <- character()

  if (!is.null(file)) {
    args <- c(args, "-f", file)
  }

  if (!is.null(devcontainer)) {
    for (dc in devcontainer) {
      args <- c(args, "-d", dc)
    }
  }

  if (!is.null(permissions)) {
    args <- c(args, "--permissions", permissions)
  }

  if (!is.null(tool)) {
    args <- c(args, "-t", tool)
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

  run_repos_script("helper/codespaces-auth-add.sh", args = args)
}

#' Run Pipeline Across Repositories
#'
#' Execute a script inside each cloned repository.
#'
#' @param file Path to repos list file (default: repos.list)
#' @param script Script to run in each repo, relative to repo root (default: run.sh)
#' @param include Character vector or comma-separated string of repo names to include
#' @param exclude Character vector or comma-separated string of repo names to exclude
#' @param ensure_setup Logical. If \code{TRUE}, clone repositories before executing scripts
#' @param skip_deps Logical. If \code{TRUE}, skip the install-r-deps.sh step
#' @param dry_run Logical. If \code{TRUE}, show what would be done without executing
#' @param verbose Logical. If \code{TRUE}, enable verbose logging
#' @param continue_on_error Logical. If \code{TRUE}, continue on failure and report all results
#' @param ... Additional arguments passed directly to the \code{run-pipeline.sh} script as-is.
#'   Useful for passing custom flags or for backward compatibility.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' This function is a wrapper around the \code{run-pipeline.sh} Bash script.
#' It will:
#' \itemize{
#'   \item Optionally clone repositories (via \code{clone-repos.sh}) before running scripts
#'   \item Optionally install R dependencies
#'   \item Execute the target script (default: \code{run.sh}) in each repository
#'   \item Print a per-repo summary at the end of execution
#' }
#'
#' @examples
#' \dontrun{
#' # Run the default script (run.sh) in each repo
#' repos_run()
#'
#' # Run a custom script
#' repos_run(script = "build.sh")
#'
#' # Continue past failures
#' repos_run(continue_on_error = TRUE)
#'
#' # Dry-run mode
#' repos_run(dry_run = TRUE)
#'
#' # Include only specific repos
#' repos_run(include = c("repo1", "repo2"))
#'
#' # Exclude specific repos
#' repos_run(exclude = "repo3")
#'
#' # Multiple options
#' repos_run(script = "test.sh", verbose = TRUE, ensure_setup = TRUE)
#'
#' # Backward compatibility - still works
#' repos_run("--script", "build.sh", "--dry-run")
#' }
#'
#' @export
repos_run <- function(file = NULL, script = NULL, include = NULL, exclude = NULL,
                      ensure_setup = FALSE, skip_deps = FALSE, dry_run = FALSE,
                      verbose = FALSE, continue_on_error = FALSE, ...) {
  args <- character()
  
  # Build argument vector from named parameters
  if (!is.null(file)) {
    args <- c(args, "-f", file)
  }
  
  if (!is.null(script)) {
    args <- c(args, "--script", script)
  }
  
  if (!is.null(include)) {
    include_str <- if (length(include) > 1) paste(include, collapse = ",") else include
    args <- c(args, "-i", include_str)
  }
  
  if (!is.null(exclude)) {
    exclude_str <- if (length(exclude) > 1) paste(exclude, collapse = ",") else exclude
    args <- c(args, "-e", exclude_str)
  }
  
  if (isTRUE(ensure_setup)) {
    args <- c(args, "--ensure-setup")
  }
  
  if (isTRUE(skip_deps)) {
    args <- c(args, "-d")
  }
  
  if (isTRUE(dry_run)) {
    args <- c(args, "-n")
  }
  
  if (isTRUE(verbose)) {
    args <- c(args, "-v")
  }
  
  if (isTRUE(continue_on_error)) {
    args <- c(args, "--continue-on-error")
  }
  
  # Append any additional arguments passed via ...
  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }
  
  run_repos_script("run-pipeline.sh", args = args)
}

#' Create a New Worktree/Branch
#'
#' Create a new worktree (or branch) off the current repository, push it to
#' origin, clean the worktree, update devcontainer.json, add the branch to
#' repos.list, and refresh the VS Code workspace file.
#'
#' @param branch_name Character string. Name of the new branch to create.
#' @param target_dir Character string. Optional custom directory name
#'   (default: \code{<repo>-<branch>}).
#' @param use_branch Logical. If \code{TRUE}, create as a separate branch
#'   instead of a worktree.
#' @param ... Additional arguments passed directly to \code{add-branch.sh}.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
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

  run_repos_script("add-branch.sh", args = args)
}

#' Update All Worktrees
#'
#' Update all worktrees with the latest devcontainer prebuild configuration.
#' Reads \code{.devcontainer/prebuild/devcontainer.json} from the base repo,
#' strips the codespaces repositories section, writes the result to
#' \code{.devcontainer/devcontainer.json} in each worktree, then commits and
#' pushes.
#'
#' @param dry_run Logical. If \code{TRUE}, show what would be done without
#'   making changes.
#' @param ... Additional arguments passed directly to \code{update-branches.sh}.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @examples
#' \dontrun{
#' repos_update_branches()
#' repos_update_branches(dry_run = TRUE)
#' }
#'
#' @export
repos_update_branches <- function(dry_run = FALSE, ...) {
  args <- character()

  if (isTRUE(dry_run)) {
    args <- c(args, "--dry-run")
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_script("update-branches.sh", args = args)
}

#' Update Scripts from Upstream
#'
#' Update scripts from the upstream CompTemplate repository. Clones/pulls
#' \code{MiguelRodo/CompTemplate} and copies all scripts from its
#' \code{scripts/} directory into the local scripts directory, then creates a
#' commit with the updates.
#'
#' @param branch Character string. Upstream branch to pull from
#'   (default: main).
#' @param dry_run Logical. If \code{TRUE}, show what would be updated without
#'   making changes.
#' @param force Logical. If \code{TRUE}, overwrite local changes without
#'   prompting.
#' @param ... Additional arguments passed directly to \code{update-scripts.sh}.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @examples
#' \dontrun{
#' repos_update_scripts()
#' repos_update_scripts(branch = "dev")
#' repos_update_scripts(dry_run = TRUE)
#' repos_update_scripts(force = TRUE)
#' }
#'
#' @export
repos_update_scripts <- function(branch = NULL, dry_run = FALSE, force = FALSE, ...) {
  args <- character()

  if (!is.null(branch)) {
    args <- c(args, "--branch", branch)
  }

  if (isTRUE(dry_run)) {
    args <- c(args, "--dry-run")
  }

  if (isTRUE(force)) {
    args <- c(args, "--force")
  }

  additional_args <- c(...)
  if (length(additional_args) > 0) {
    args <- c(args, additional_args)
  }

  run_repos_script("update-scripts.sh", args = args)
}
