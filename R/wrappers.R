#' Multi-Repository Management Tool
#'
#' Runs the repos setup script to manage multiple related Git repositories.
#'
#' @param ... Additional arguments passed to the setup-repos.sh script.
#'   Common options include:
#'   \itemize{
#'     \item \code{-f FILE}: Use a different repos list file (default: repos.list)
#'     \item \code{--public}: Create repositories as public (default is private)
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
#' The repositories are specified in a \code{repos.list} file in your current directory.
#'
#' @examples
#' \dontrun{
#' # Setup repositories from default repos.list
#' repos()
#'
#' # Use a different file
#' repos("-f", "my-repos.list")
#'
#' # Create repositories as public
#' repos("--public")
#'
#' # Show help
#' repos("--help")
#' }
#'
#' @export
repos <- function(...) {
  # Find the script path
  script_path <- system.file("scripts/setup-repos.sh", package = "repos")
  
  # Check if script exists
  if (script_path == "" || !file.exists(script_path)) {
    stop("Cannot find setup-repos.sh script. Make sure the package is properly installed.")
  }
  
  # Prepare arguments
  args <- c(...)
  
  # Run the script (output is shown to the user)
  exit_status <- system2(script_path, args = args)
  
  # Return exit status invisibly
  invisible(exit_status)
}
