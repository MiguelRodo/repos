#!/usr/bin/env Rscript
# Test R wrapper functions with idiomatic syntax

# Load the wrappers code
source("R/wrappers.R")

# Mock system2 to capture repos binary invocations
test_args <- NULL
system2 <- function(command, args = character(), stdout = "", stderr = "", ...) {
  test_args <<- list(command = command, args = args)
  0L
}

test_count <- 0
pass_count <- 0
fail_count <- 0

test <- function(description, expr) {
  test_count <<- test_count + 1
  cat(sprintf("Test %d: %s... ", test_count, description))
  
  result <- tryCatch({
    eval(expr)
    TRUE
  }, error = function(e) {
    cat(sprintf("FAILED\n  Error: %s\n", e$message))
    FALSE
  })
  
  if (result) {
    cat("PASSED\n")
    pass_count <<- pass_count + 1
  } else {
    fail_count <<- fail_count + 1
  }
}

# Test repos_workspace with idiomatic syntax
test("repos_workspace() with no args", {
  repos_workspace()
  stopifnot(test_args$command == "repos")
  stopifnot(length(test_args$args) == 1)
  stopifnot(test_args$args[1] == "workspace")
})

test("repos_workspace(file = 'custom.list')", {
  repos_workspace(file = "custom.list")
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "workspace")
  stopifnot(any(test_args$args == "-f"))
  stopifnot(any(test_args$args == "custom.list"))
})

test("repos_workspace(debug = TRUE)", {
  repos_workspace(debug = TRUE)
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "workspace")
  stopifnot("--debug" %in% test_args$args)
})

# Test repos_codespace with idiomatic syntax
test("repos_codespace() with no args", {
  repos_codespace()
  stopifnot(test_args$command == "repos")
  stopifnot(length(test_args$args) == 1)
  stopifnot(test_args$args[1] == "codespace")
})

test("repos_codespace(file = 'custom.list')", {
  repos_codespace(file = "custom.list")
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "codespace")
  stopifnot(any(test_args$args == "-f"))
  stopifnot(any(test_args$args == "custom.list"))
})

test("repos_codespace(devcontainer = c('path1', 'path2'))", {
  repos_codespace(devcontainer = c("path1", "path2"))
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "codespace")
  dc_indices <- which(test_args$args == "-d")
  stopifnot(length(dc_indices) == 2)
  stopifnot(test_args$args[dc_indices[1] + 1] == "path1")
  stopifnot(test_args$args[dc_indices[2] + 1] == "path2")
})

test("repos_codespace(permissions = 'all')", {
  repos_codespace(permissions = "all")
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "codespace")
  stopifnot("--permissions" %in% test_args$args)
  stopifnot("all" %in% test_args$args)
})

test("repos_codespace(debug = TRUE)", {
  repos_codespace(debug = TRUE)
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "codespace")
  stopifnot("--debug" %in% test_args$args)
})

# Test repos_run with idiomatic syntax
test("repos_run() with no args", {
  repos_run()
  stopifnot(test_args$command == "repos")
  stopifnot(length(test_args$args) == 1)
  stopifnot(test_args$args[1] == "run")
})

test("repos_run(script = 'build.sh')", {
  repos_run(script = "build.sh")
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "run")
  stopifnot(any(test_args$args == "--script"))
  stopifnot(any(test_args$args == "build.sh"))
})

test("repos_run(dry_run = TRUE, verbose = TRUE)", {
  repos_run(dry_run = TRUE, verbose = TRUE)
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "run")
  stopifnot("--dry-run" %in% test_args$args)
  stopifnot("--verbose" %in% test_args$args)
})

test("repos_run(include = c('repo1', 'repo2'))", {
  repos_run(include = c("repo1", "repo2"))
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "run")
  i_idx <- which(test_args$args == "-i")
  stopifnot(length(i_idx) == 1)
  stopifnot(test_args$args[i_idx + 1] == "repo1,repo2")
})

test("repos_run(exclude = 'repo3')", {
  repos_run(exclude = "repo3")
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "run")
  e_idx <- which(test_args$args == "-e")
  stopifnot(length(e_idx) == 1)
  stopifnot(test_args$args[e_idx + 1] == "repo3")
})

test("repos_run(ensure_setup = TRUE, skip_deps = TRUE)", {
  repos_run(ensure_setup = TRUE, skip_deps = TRUE)
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "run")
  stopifnot("--ensure-setup" %in% test_args$args)
  stopifnot("--skip-deps" %in% test_args$args)
})

test("repos_run(continue_on_error = TRUE)", {
  repos_run(continue_on_error = TRUE)
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "run")
  stopifnot("--continue-on-error" %in% test_args$args)
})

# Test backward compatibility
test("repos_run('--script', 'test.sh') backward compatibility", {
  repos_run("--script", "test.sh")
  stopifnot(test_args$command == "repos")
  stopifnot(test_args$args[1] == "run")
  stopifnot("--script" %in% test_args$args)
  stopifnot("test.sh" %in% test_args$args)
})

# Summary
cat("\n")
cat("========================================\n")
cat(sprintf("Total tests: %d\n", test_count))
cat(sprintf("Passed: %d\n", pass_count))
cat(sprintf("Failed: %d\n", fail_count))
cat("========================================\n")

if (fail_count > 0) {
  quit(status = 1)
}
