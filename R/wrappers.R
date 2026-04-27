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
#'   \code{"codespaces"}, or \code{"run"}.
#' @param ... Additional arguments passed to the underlying script.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' \code{repos("clone", ...)} delegates to \code{clone-repos.sh}.
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
#' @examples
#' \dontrun{
#' repos("clone")
#' repos("workspace")
#' repos("codespace")
#' repos("run")
#' repos("run", script = "build.sh")
#' }
#'
#' @export
repos <- function(command, ...) {
  valid <- c("clone", "workspace", "codespace", "codespaces", "run")
  if (missing(command) || !(command %in% valid)) {
    message("Usage: repos(command, ...)\n")
    message("Commands:")
    message("  \"clone\"      Clone repositories listed in repos.list")
    message("  \"workspace\"  Generate or update the VS Code workspace file")
    message("  \"codespace\"  Configure GitHub Codespaces authentication")
    message("  \"run\"        Execute a script inside each cloned repository")
    message("\nSee ?repos_workspace, ?repos_codespace and ?repos_run for details.")
    return(invisible(1L))
  }

  switch(command,
    clone      = run_repos_script("helper/clone-repos.sh", args = c(...)),
    workspace  = repos_workspace(...),
    codespace  = repos_codespace(...),
    codespaces = repos_codespace(...),
    run        = repos_run(...)
  )
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
#' multi-root workspace in VS Code or Positron.
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
