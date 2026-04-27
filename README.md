# repos - Multi-Repository Management Tool

[![Test Installation Methods](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml)
[![Test Suite](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml)

Manage multiple Git repositories as a unified workspace from a single `repos.list` file.

## Quick Start

Create a `repos.list` file in your project directory listing the repositories you want:

```
myorg/data-curation
myorg/analysis
myorg/documentation
```

Then run:

```bash
repos setup
```

This clones all listed repositories into the parent directory of your current location.

## What else can you do?

**Customise `repos.list`** — clone specific branches (`owner/repo@branch`), use
worktrees (`@branch-name`), set repository visibility (`--public`/`--private`),
and more. → [repos.list reference](https://miguelrodo.github.io/repos/repos-list.html)

**`repos setup`** — beyond cloning, it generates a VS Code workspace file, configures
GitHub Codespaces authentication (`--codespaces`), and handles devcontainer paths.
→ [repos setup guide](https://miguelrodo.github.io/repos/setup.html)

**Run a pipeline across all repos** — if your repositories contain a `run.sh` script
(or any script you specify), `repos run` executes it in each one.
→ [Running pipelines](https://miguelrodo.github.io/repos/pipelines.html)

## Installation

→ [Installation guide](https://miguelrodo.github.io/repos/install.html)

## License

MIT License — see [debian/copyright](debian/copyright)

## Contributing

Issues and pull requests welcome at <https://github.com/MiguelRodo/repos>

## Author

Miguel Rodo \<miguel.rodo@uct.ac.za\>
