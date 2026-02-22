# AGENTS.md

Configuration for AI coding agents (e.g., Google Jules, GitHub Copilot) working in this repository.

---

## Core Philosophy / Project Context

`repos` is a command-line tool for managing multiple related Git repositories as a unified workspace. The primary workflow is:

1. A user creates a `repos.list` file listing repositories (and optionally branches) they want cloned.
2. Running `repos setup` clones them all into the **parent directory** of the current location, creating the remote repositories on GitHub (via the API) if they do not already exist.
3. Running `repos run` executes a script inside each cloned repository.

The codebase is built around **Bash scripts** as the core engine. Language wrappers (R and Python) exist to expose the same functionality from those runtimes by bundling and invoking the Bash scripts via `system2()` / `subprocess.run()`.

Key architectural patterns:
- All real logic lives in `scripts/` (and `scripts/helper/`); the top-level `bin/repos` dispatcher delegates to them.
- Repositories are always cloned to the **parent directory** of the working directory — never inside it.
- Branch-only clones use Git **worktrees**, not fresh clones.
- Fallback repository logic: a bare `@<branch>` line reuses the most recently seen repo (or the current repo's remote if none has been seen yet).

---

## Tech Stack & Tooling

### Core
| Layer | Technology |
|---|---|
| Shell | **Bash** (POSIX-compatible where possible) |
| VCS | **Git** (including `git worktree`) |
| HTTP / GitHub API | **curl** + **jq** |
| GitHub auth | `GH_TOKEN` env var or `gh` CLI |

### Language Wrappers
| Language | Entry point |
|---|---|
| R | `R/` package; functions in `R/repos.R` |
| Python | `src/repos/` package; entry point `src/repos/__init__.py` |

### Packaging
| Platform | Format |
|---|---|
| Ubuntu / Debian | `.deb` (built with `dpkg-buildpackage`) |
| macOS | Homebrew formula (`homebrew/`) |
| Windows | Scoop manifest (`scoop/`) |
| Language | pip (`pyproject.toml`), devtools/GitHub (`DESCRIPTION`) |

### Do **not** use
- Any shell other than Bash for new scripts (avoid `zsh`-only or `fish` syntax).
- Python or R for core logic — keep the Bash scripts as the single source of truth.
- External tools beyond `bash`, `git`, `curl`, and `jq` as hard runtime dependencies.

---

## Setup Commands

```bash
# Clone the repository
git clone https://github.com/MiguelRodo/repos.git
cd repos

# Install to ~/.local/bin (no sudo required)
bash install-local.sh

# Verify installation
repos --help
```

If `~/.local/bin` is not on your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
# Persist by adding the line above to ~/.bashrc or ~/.profile
```

### Runtime dependencies

```bash
# Ubuntu / Debian
sudo apt-get install bash git curl jq

# macOS (Homebrew)
brew install git curl jq
```

---

## Build & Test Instructions

### Running the test suite

Tests are plain Bash scripts located in `tests/`. Run them individually or all at once:

```bash
# Run a specific test
bash tests/test-setup-repos-local.sh

# Run all tests (from the repo root)
for t in tests/test-*.sh; do
  echo "==> $t"
  bash "$t"
done
```

Notable test files:
| File | What it covers |
|---|---|
| `tests/test-setup-repos-local.sh` | Full integration test using local bare git remotes (no network required) |
| `tests/test-repos-list-flags.sh` | Parsing of global and per-line flags in `repos.list` |
| `tests/test-auth-check.sh` | GitHub token validation logic |
| `tests/test-clone-repos-flags.sh` | Flag handling in `clone-repos.sh` |
| `tests/test-worktree-tracking.sh` | Worktree creation and tracking |

### Linting / static analysis

No automated linter is currently configured in CI/CD. When editing Bash scripts, follow `shellcheck` best practices:

```bash
# Install shellcheck
sudo apt-get install shellcheck   # Ubuntu/Debian
brew install shellcheck           # macOS

# Lint a script
shellcheck scripts/setup-repos.sh
shellcheck scripts/helper/clone-repos.sh
```

### Python package (optional)

```bash
pip install -e .          # Install in editable mode
python -c "from repos import setup; print('ok')"
```

### R package (optional)

```r
devtools::load_all()      # Load package for development
devtools::test()          # Run R tests (if any)
```

---

## Coding Style & Conventions

### Bash scripts
- Use `set -e` at the top of every script to fail fast on errors.
- Use `mktemp` (never predictable `/tmp/$name_$$`) for temporary files.
- Quote all variable expansions: `"$var"`, `"${arr[@]}"`.
- Use `local` for variables inside functions.
- Sanitize filesystem names derived from branch names by replacing `/` with `-` (e.g., `feature/x` → `feature-x` for directory names, while the actual git branch name is preserved).
- Add a brief comment header at the top of each script describing its purpose.

### Git commits
- Use the imperative mood in the subject line: *"Add flag for --public"*, not *"Added …"*.
- Keep the subject line under 72 characters.
- Reference the relevant issue or PR where applicable.

### Pull requests
- One logical change per PR.
- All existing tests must pass before merging.
- Add or update tests in `tests/` when changing script behaviour.
- Do not introduce new runtime dependencies without updating the *Dependencies* section in `README.md`.
