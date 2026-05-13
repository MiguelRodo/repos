# AGENTS.md

Configuration for AI coding agents (e.g., Google Jules, GitHub Copilot) working in this repository.

---

## Core Philosophy / Project Context

`repos` is a command-line tool for managing multiple related Git repositories as a unified workspace.

### Pure Go Implementation
Historically, this project was built on Bash 3.2-compatible scripts (designed to work in environments like Git Bash on Windows) with a CLI frontend and language wrappers (R and Python) that shelled out to those scripts.

**That transition is complete: `repos` is implemented as a pure Go CLI (`cmd/repos/`).**

When modifying or extending the tool:
- **Do NOT add shell-script command implementations back into the project.**
- The Go commands must be fully self-contained and implemented in pure Go (with the exception of shelling out to `git` or `gh` where unavoidable, though native Go solutions are preferred when practical).
- Do not rely on external tools like `jq`, `curl`, Python, or R inside the Go codebase. Use standard Go libraries (e.g., `encoding/json`, `net/http`).

### Documentation
- The `README.md` provides a concise overview of the project.
- Detailed documentation is available on the project's website, which is structured with roughly one page per command (e.g., `clone.qmd`, `install.qmd`, `pipelines.qmd`, `worktrees.qmd`). Consult these files for intended user-facing behavior.

### Key Architectural Patterns
1. A user creates a `repos.list` file listing repositories (and optionally branches) they want cloned.
2. Repositories are always cloned to the **parent directory** of the working directory — never inside it.
3. Branch-only clones clone only that branch down (before, by default, allowing `git fetch` to fetch all remote branches), or else use Git **worktrees** rather than fresh full clones to save space and simplify management.
4. Fallback repository logic: a bare `@<branch>` line reuses the most recently seen repo (or the current repo's remote if none has been seen yet).

---

## Tech Stack & Tooling

### Core
| Layer | Technology |
|---|---|
| CLI Application | **Go** (`cmd/repos/`) |
| VCS | **Git** (including `git worktree`) |
| GitHub auth | `GH_TOKEN` env var or `gh` CLI |

### Wrappers
| Language | Entry point |
|---|---|
| R | `R/` package; functions in `R/wrappers.R` |
| Python | `src/repos/` package; entry point `src/repos/__init__.py` |

---

## Build & Test Instructions

### Running the Go Tests

All new functionality should be covered by Go tests.

```bash
# Run the Go test suite
cd cmd/repos
go test ./... -v
```

### Wrapper Tests
Run wrapper checks with:

```bash
python tests/test-python-wrappers.py
Rscript tests/test-r-wrappers.R
```

---

## Coding Style & Conventions

### Go Code
- Follow standard Go idioms and formatting (`gofmt`).
- Ensure robust error handling. Do not silently ignore errors unless explicitly documented why.
- Keep commands encapsulated in their respective files (e.g., `clone.go`, `create.go`, `run.go`).

### Git Commits
- Use the imperative mood in the subject line: *"Add flag for --public"*, not *"Added …"*.
- Keep the subject line under 72 characters.
- Reference the relevant issue or PR where applicable.

### Pull Requests
- One logical change per PR.
- All existing tests must pass before merging.
- Add or update tests when changing behavior.
- Ensure the changes adhere to the "Pure Go" mandate for the CLI.
