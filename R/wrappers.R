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
#'   Must be one of \code{"setup"} or \code{"run"}.
#' @param ... Additional arguments passed to the underlying script.
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' \code{repos("setup", ...)} delegates to \code{setup-repos.sh} (see
#' \code{\link{repos_setup}}).
#'
#' \code{repos("run", ...)} delegates to \code{run-pipeline.sh} (see
#' \code{\link{repos_run}}).
#'
#' @examples
#' \dontrun{
#' repos("setup")
#' repos("setup", "--public")
#' repos("run", "--skip-setup")
#' repos("run", "--skip-setup", "--script", "build.sh")
#' }
#'
#' @export
repos <- function(command, ...) {
  if (missing(command) || !(command %in% c("setup", "run"))) {
    message("Usage: repos(command, ...)\n")
    message("Commands:")
    message("  \"setup\"  Clone and configure repositories from a repos.list file")
    message("  \"run\"    Execute a script inside each cloned repository")
    message("\nSee ?repos_setup and ?repos_run for details.")
    return(invisible(1L))
  }

  switch(command,
    setup = repos_setup(...),
    run   = repos_run(...)
  )
}

#' Setup Repositories
#'
#' Clone and configure repositories from a \code{repos.list} file.
#'
#' @param ... Additional arguments passed to the \code{setup-repos.sh} script.
#'   Common options include:
#'   \itemize{
#'     \item \code{-f FILE}: Use a different repos list file (default: repos.list)
#'     \item \code{--public}: Create repositories as public (default is private)
#'     \item \code{--codespaces}: Enable Codespaces authentication
#'     \item \code{--help}: Show help message
#'   }
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' This function is a wrapper around the \code{setup-repos.sh} Bash script.
#' It will:
#' \itemize{
#'   \item Create any missing repositories on GitHub (if you have permissions)
#'   \item Clone all specified repositories to the parent directory
#'   \item Generate a VS Code workspace file
#'   \item Configure authentication for GitHub Codespaces
#' }
#'
#' The repositories are specified in a \code{repos.list} file in your current
#' directory.
#'
#' @examples
#' \dontrun{
#' # Setup repositories from default repos.list
#' repos_setup()
#'
#' # Use a different file
#' repos_setup("-f", "my-repos.list")
#'
#' # Create repositories as public
#' repos_setup("--public")
#'
#' # Show help
#' repos_setup("--help")
#' }
#'
#' @export
repos_setup <- function(...) {
  run_repos_script("setup-repos.sh", args = c(...))
}

#' Run Pipeline Across Repositories
#'
#' Execute a script inside each cloned repository.
#'
#' @param ... Additional arguments passed to the \code{run-pipeline.sh} script.
#'   Common options include:
#'   \itemize{
#'     \item \code{-f FILE}: Repo list file (default: repos.list)
#'     \item \code{--script PATH}: Script to run in each repo (default: run.sh)
#'     \item \code{-s, --skip-setup}: Skip the setup-repos.sh step
#'     \item \code{-d, --skip-deps}: Skip the install-r-deps.sh step
#'     \item \code{-i, --include NAMES}: Comma-separated repo names to include
#'     \item \code{-e, --exclude NAMES}: Comma-separated repo names to exclude
#'     \item \code{-n, --dry-run}: Show what would be done without executing
#'     \item \code{--no-stop-on-error}: Continue on failure, report all results
#'     \item \code{--help}: Show help message
#'   }
#'
#' @return Invisibly returns the exit status of the script (0 for success).
#'
#' @details
#' This function is a wrapper around the \code{run-pipeline.sh} Bash script.
#' It will:
#' \itemize{
#'   \item Optionally run \code{setup-repos.sh} to ensure repos are cloned
#'   \item Optionally install R dependencies
#'   \item Execute the target script (default: \code{run.sh}) in each repository
#'   \item Print a per-repo summary at the end of execution
#' }
#'
#' @examples
#' \dontrun{
#' # Run the default script (run.sh) in each repo, skipping setup
#' repos_run("--skip-setup")
#'
#' # Run a custom script
#' repos_run("--skip-setup", "--script", "build.sh")
#'
#' # Continue past failures
#' repos_run("--skip-setup", "--no-stop-on-error")
#'
#' # Dry-run mode
#' repos_run("--skip-setup", "--dry-run")
#'
#' # Show help
#' repos_run("--help")
#' }
#'
#' @export
repos_run <- function(...) {
  run_repos_script("run-pipeline.sh", args = c(...))
}
