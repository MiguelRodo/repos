# repos - Multi-Repository Management Tool

[![Test Installation Methods](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml)
[![Test Suite](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml)
[![R-CMD-check](https://github.com/MiguelRodo/repos/actions/workflows/R-CMD-check.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/R-CMD-check.yml)
[![Python package](https://github.com/MiguelRodo/repos/actions/workflows/python-package.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/python-package.yml)

`repos` is a Go command-line utility for managing multiple Git repositories as a
unified workspace from a single `repos.list` file.

## Installation

Install on Linux, macOS, or Windows, with optional R and Python wrappers.
→ [Full installation guide](https://miguelrodo.github.io/repos/install.html)

Common install paths:

```bash
# Go (from source)
go install github.com/MiguelRodo/repos/v2/cmd/repos@latest
```

## Quick Start

Create a `repos.list` file in your project directory listing the repositories you want:

```
myorg/data-curation
myorg/analysis
myorg/documentation
hf:datasets/huggingface/stack
```

Then run:

```bash
repos clone
```

This clones all listed repositories into the parent directory of your current location.
Hugging Face entries (`hf:...`) require `huggingface-cli`
(`pip install huggingface_hub[cli]`).

### Fetch modes

`repos clone` supports explicit fetch behaviour:

- `--fetch-all-deferred` *(default)*: fast `--single-branch` clone, then restore wildcard fetch refspec
- `--fetch-single`: keep strict single-branch refspec isolation
- `--fetch-all`: full clone with all branches fetched upfront
- `--depth <n>`: opt-in shallow clone depth (fast clone with truncated history)

## Commands and capabilities

- `repos clone` — clone repos listed in `repos.list` (including branch/worktree
  patterns and fetch modes)
- `repos workspace` — generate or refresh `entire-project.code-workspace`
- `repos run` — run scripts or explicit commands across managed repos
- `repos create` — create missing GitHub repos from `repos.list`
- `repos codespace` — configure `GH_TOKEN` Codespaces secrets and devcontainer
  repository permissions
- `repos install-r-deps` — install R dependencies across managed repos

`repos.list` supports specific branches (`owner/repo@branch`), fallback
`@branch` entries, Hugging Face entries (`hf:owner/repo@revision`), worktrees,
visibility flags, and global flags.
→ [repos.list reference](https://miguelrodo.github.io/repos/repos-list.html)

**Run a pipeline across all repos** — run `run.sh` (or another script), or run
an explicit command in each repo.
→ [Running pipelines](https://miguelrodo.github.io/repos/pipelines.html)

**IDE integration** — generate VS Code/Positron workspace files and set up
Codespaces auth.
→ [VS Code integration](https://miguelrodo.github.io/repos/vscode.html)

**R and Python wrappers** — both wrappers call the installed `repos` CLI.
→ [R package docs](https://miguelrodo.github.io/repos/r-package.html)  
→ [Python package docs](https://miguelrodo.github.io/repos/python-package.html)

## License

MIT License — see [debian/copyright](debian/copyright)

## Contributing

Issues and pull requests welcome at <https://github.com/MiguelRodo/repos>

## Author

Miguel Rodo \<miguel.rodo@uct.ac.za\>
