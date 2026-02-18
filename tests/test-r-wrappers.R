#!/usr/bin/env Rscript
# Test R wrapper functions with idiomatic syntax

# Mock run_repos_script to capture arguments
test_args <- NULL
run_repos_script <- function(script_name, args = character()) {
  test_args <<- list(script = script_name, args = args)
  invisible(0)
}

# Load the wrappers code
source("R/wrappers.R")

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

# Test repos_setup with idiomatic syntax
test("repos_setup() with no args", {
  repos_setup()
  stopifnot(test_args$script == "setup-repos.sh")
  stopifnot(length(test_args$args) == 0)
})

test("repos_setup(public = TRUE)", {
  repos_setup(public = TRUE)
  stopifnot(test_args$script == "setup-repos.sh")
  stopifnot("--public" %in% test_args$args)
})

test("repos_setup(file = 'custom.list')", {
  repos_setup(file = "custom.list")
  stopifnot(test_args$script == "setup-repos.sh")
  stopifnot(any(test_args$args == "-f"))
  stopifnot(any(test_args$args == "custom.list"))
})

test("repos_setup(public = TRUE, codespaces = TRUE)", {
  repos_setup(public = TRUE, codespaces = TRUE)
  stopifnot(test_args$script == "setup-repos.sh")
  stopifnot("--public" %in% test_args$args)
  stopifnot("--codespaces" %in% test_args$args)
})

test("repos_setup(devcontainer = c('path1', 'path2'))", {
  repos_setup(devcontainer = c("path1", "path2"))
  stopifnot(test_args$script == "setup-repos.sh")
  dc_indices <- which(test_args$args == "-d")
  stopifnot(length(dc_indices) == 2)
  stopifnot(test_args$args[dc_indices[1] + 1] == "path1")
  stopifnot(test_args$args[dc_indices[2] + 1] == "path2")
})

test("repos_setup(debug = TRUE)", {
  repos_setup(debug = TRUE)
  stopifnot(test_args$script == "setup-repos.sh")
  stopifnot("--debug" %in% test_args$args)
})

# Test backward compatibility
test("repos_setup('--public') backward compatibility", {
  repos_setup("--public")
  stopifnot(test_args$script == "setup-repos.sh")
  stopifnot("--public" %in% test_args$args)
})

# Test repos_run with idiomatic syntax
test("repos_run() with no args", {
  repos_run()
  stopifnot(test_args$script == "run-pipeline.sh")
  stopifnot(length(test_args$args) == 0)
})

test("repos_run(script = 'build.sh')", {
  repos_run(script = "build.sh")
  stopifnot(test_args$script == "run-pipeline.sh")
  stopifnot(any(test_args$args == "--script"))
  stopifnot(any(test_args$args == "build.sh"))
})

test("repos_run(dry_run = TRUE, verbose = TRUE)", {
  repos_run(dry_run = TRUE, verbose = TRUE)
  stopifnot(test_args$script == "run-pipeline.sh")
  stopifnot("-n" %in% test_args$args)
  stopifnot("-v" %in% test_args$args)
})

test("repos_run(include = c('repo1', 'repo2'))", {
  repos_run(include = c("repo1", "repo2"))
  stopifnot(test_args$script == "run-pipeline.sh")
  i_idx <- which(test_args$args == "-i")
  stopifnot(length(i_idx) == 1)
  stopifnot(test_args$args[i_idx + 1] == "repo1,repo2")
})

test("repos_run(exclude = 'repo3')", {
  repos_run(exclude = "repo3")
  stopifnot(test_args$script == "run-pipeline.sh")
  e_idx <- which(test_args$args == "-e")
  stopifnot(length(e_idx) == 1)
  stopifnot(test_args$args[e_idx + 1] == "repo3")
})

test("repos_run(ensure_setup = TRUE, skip_deps = TRUE)", {
  repos_run(ensure_setup = TRUE, skip_deps = TRUE)
  stopifnot(test_args$script == "run-pipeline.sh")
  stopifnot("--ensure-setup" %in% test_args$args)
  stopifnot("-d" %in% test_args$args)
})

test("repos_run(continue_on_error = TRUE)", {
  repos_run(continue_on_error = TRUE)
  stopifnot(test_args$script == "run-pipeline.sh")
  stopifnot("--continue-on-error" %in% test_args$args)
})

# Test backward compatibility
test("repos_run('--script', 'test.sh') backward compatibility", {
  repos_run("--script", "test.sh")
  stopifnot(test_args$script == "run-pipeline.sh")
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
