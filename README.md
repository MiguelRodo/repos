# repos - Multi-Repository Management Tool

[![Test Installation Methods](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml)
[![Test Suite](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml)

A command-line tool for managing multiple related Git repositories as a unified workspace.

## Overview

Many projects consist of multiple repositories. For instance, an analysis project might have one repository for data curation and another for analysis. To facilitate this workflow, you can create a repos.list file that specifies the repositories and their branches, and then run repos to clone them (creating repositories as needed if you have permissions).

Here's an example repos.list file:

```
myorg/data-curation
myorg/analysis@main
myorg/documentation
```

Run repos to clone them:

```bash
repos
```

This creates the following directory structure:

```
workspace/
├── my-project/          # Your main project (contains repos.list)
├── data-curation/       # Cloned from myorg/data-curation
├── analysis-main/       # Cloned from myorg/analysis@main
└── documentation/       # Cloned from myorg/documentation
```

### Customizations

- Create repositories as public using the --public flag
- Specify a different repos.list file with -f my-repos.list
- Enable Codespaces authentication with --codespaces
- Specify custom devcontainer paths with -d
- Clone specific branches using owner/repo@branch syntax
- Create worktrees from the current repository using @branch-name

## Installation

You can install repos as a system package (Ubuntu/Debian, macOS, Windows), from source, or as a language-specific wrapper (R or Python).

### <a name="ubuntu-debian"></a>Ubuntu/Debian

Install the .deb package to use the repos command system-wide.

Download and install the latest `.deb` package from the [Releases page](https://github.com/MiguelRodo/repos/releases):

```bash
# Download the latest release (replace VERSION_REPOS with desired version; we try to ensure this is the latest one)
VERSION_REPOS=1.0.9
wget https://github.com/MiguelRodo/repos/releases/download/v${VERSION_REPOS}/repos_${VERSION_REPOS}_all.deb

# Install the package
sudo dpkg -i repos_${VERSION_REPOS}_all.deb

# Remove installation file
rm repos_${VERSION_REPOS}_all.deb

# If there are dependency issues, run:
sudo apt-get install -f
```

Run the repos command:

```bash
repos
```

#### Dependencies

The package automatically handles dependencies, but requires:
- `bash` - Shell interpreter
- `git` - Version control
- `curl` - HTTP client
- `jq` - JSON processor

These are typically pre-installed on Ubuntu/Debian systems. If not:

```bash
sudo apt-get install bash git curl jq
```

### <a name="windows-scoop"></a>Windows (Scoop)

Install using Scoop to use the repos command in your shell.

Install using [Scoop](https://scoop.sh/):

```powershell
# Add the repos bucket (replace <username> with the bucket owner)
scoop bucket add repos https://github.com/<username>/scoop-bucket

# Install repos
scoop install repos
```

Run the repos command:

```powershell
repos
```

Dependencies (`git` and `jq`) are automatically installed by Scoop. You'll also need Git for Windows for bash support.

### <a name="windows-manual"></a>Windows (Manual)

Install manually to use the repos command in PowerShell or Git Bash.

1. Clone the repository:
   ```powershell
   git clone https://github.com/MiguelRodo/repos.git
   cd repos
   ```

2. Run the installer:
   ```powershell
   .\install.ps1
   ```

3. Restart your PowerShell session for the PATH changes to take effect.

4. Verify installation:
   ```powershell
   repos --help
   ```

Run the repos command:

```powershell
repos
```

#### Windows Dependencies

- **Git for Windows** (required for bash, git, and curl): [Download here](https://git-scm.com/download/win)
- **jq** (required for JSON processing): [Download here](https://jqlang.github.io/jq/download/)

### <a name="macos-homebrew"></a>macOS (Homebrew)

Install using Homebrew to use the repos command system-wide.

Install using [Homebrew](https://brew.sh/):

```bash
# Add the repos tap (replace <username> with the tap owner)
brew tap <username>/repos

# Install repos
brew install repos
```

Run the repos command:

```bash
repos
```

The formula automatically handles the `jq` dependency. Git is typically pre-installed on macOS.

### <a name="from-source"></a>From Source

Install from source to use the repos command or run scripts directly.

```bash
git clone https://github.com/MiguelRodo/repos.git
cd repos

# For Ubuntu/Debian
sudo dpkg-buildpackage -us -uc -b
sudo dpkg -i ../repos_*.deb

# For other systems, use the scripts directly
./scripts/setup-repos.sh
```

Run the repos command:

```bash
repos
```

### <a name="language-wrappers"></a>Language Wrappers

The repository also provides native R and Python packages that wrap the underlying Bash scripts, making it easy to use repos from your preferred language environment.

#### <a name="r-package"></a>R Package

Install the R package to use repos from within R.

Install directly from GitHub using `devtools`:

```r
# Install devtools if you haven't already
install.packages("devtools")

# Install repos package
devtools::install_github("MiguelRodo/repos")

# Use the repos function
library(repos)
repos()  # Run with default repos.list

# Or with options
repos("-f", "my-repos.list")
repos("--public")
repos("--help")
```

Run the repos command:

```r
library(repos)
repos()
```

**System Requirements:** The R package requires `bash`, `git`, `curl`, and `jq` to be installed on your system.

**How it works:** The R package bundles the Bash scripts in `inst/scripts/` and provides a wrapper function that locates and executes them using `system2()`.

#### <a name="python-package"></a>Python Package

Install the Python package to use repos from Python or the command line.

Install using pip:

```bash
# Install from local clone
git clone https://github.com/MiguelRodo/repos.git
cd repos
pip install .

# Or install in development mode
pip install -e .

# Use the repos command
repos  # Run with default repos.list
repos -f my-repos.list
repos --public
repos --help
```

Run the repos command:

```bash
repos
```

**System Requirements:** The Python package requires `bash`, `git`, `curl`, and `jq` to be installed on your system. On Windows, you need [Git for Windows](https://git-scm.com/download/win) (which includes Git Bash) or WSL (Windows Subsystem for Linux).

**How it works:** The Python package bundles the Bash scripts in `src/repos/scripts/` and provides both a CLI entry point and a Python API using `subprocess.run()`.

**Python API:**

```python
from repos import run_script

# Run the setup script
run_script("setup-repos.sh", ["-f", "my-repos.list"])

# Run other scripts
run_script("run-pipeline.sh")
run_script("add-branch.sh", ["feature-x"])
```

## Quick Start

### 1. Create a repos.list file

Create a `repos.list` file in your project directory:

```bash
# Clone full repository
owner/repo

# Clone specific branch
owner/repo@branch

# Create worktree from current repo
@branch-name

# Clone with custom directory name
owner/repo custom-name
```

**Example:**

```bash
# repos.list
myorg/backend
myorg/frontend@develop
myorg/docs
```

### 2. Run setup

```bash
repos
```

This will:
1. Create any missing repositories on GitHub (if you have permissions)
2. Clone all specified repositories to the parent directory
3. Generate a VS Code workspace file

To also configure authentication for GitHub Codespaces, use the `--codespaces` flag or specify devcontainer paths with `-d`:

```bash
# Enable Codespaces authentication with default path
repos --codespaces

# Specify custom devcontainer.json paths
repos -d .devcontainer/devcontainer.json
repos -d path1/devcontainer.json -d path2/devcontainer.json
```

## Usage

### Basic Commands

The `repos` command is a wrapper around `setup-repos.sh`. All options are passed through:

```bash
# Setup repositories from repos.list
repos

# Use a different file
repos -f my-repos.list

# Create repositories as public (default is private)
repos --public

# Enable Codespaces authentication
repos --codespaces

# Specify custom devcontainer.json paths
repos -d .devcontainer/devcontainer.json

# Show help
repos --help
```

### Advanced Features

The package installs additional scripts to `/usr/share/repos/scripts/` that you can call directly:

```bash
# Execute pipeline across all repositories
/usr/share/repos/scripts/run-pipeline.sh

# Create worktrees for parallel development
/usr/share/repos/scripts/add-branch.sh feature-x

# Sync devcontainer across worktrees
/usr/share/repos/scripts/update-branches.sh

# Pull latest scripts from template
/usr/share/repos/scripts/update-scripts.sh
```

**Note for contributors:** When developing/testing from the repository, you can run scripts directly:
```bash
scripts/setup-repos.sh
scripts/run-pipeline.sh
```

### Repository Layout

All repositories are cloned to the **parent directory** of your current location:

```
workspace/
├── my-project/          # Your main project (contains repos.list)
├── backend/             # Cloned from myorg/backend
├── frontend-develop/    # Cloned from myorg/frontend@develop
└── docs/                # Cloned from myorg/docs
```

### repos.list Format

```bash
# Full repository clone
owner/repo

# Specific branch clone
owner/repo@branch

# Worktree from current repository
@branch-name [optional-target-directory]

# External repository with custom directory
owner/repo custom-directory
```

### Running Pipelines

If your repositories contain `run.sh` scripts, you can execute them across all repositories:

```bash
/usr/share/repos/scripts/run-pipeline.sh

# With options
/usr/share/repos/scripts/run-pipeline.sh --skip-setup
/usr/share/repos/scripts/run-pipeline.sh --include "backend,frontend"
/usr/share/repos/scripts/run-pipeline.sh --dry-run
```

## Configuration

### GitHub Authentication

For private repositories or creating repos, you need GitHub credentials:

```bash
# Set GitHub token
export GH_TOKEN="your_github_personal_access_token"

# Or use gh CLI
gh auth login

# For Codespaces, add GH_TOKEN as a secret
```

### VS Code Workspace

After running `repos`, open the generated workspace:

```bash
code entire-project.code-workspace
```

## Examples

### Example 1: Clone multiple repositories

```bash
# repos.list
user/web-app
user/api-server
user/database-scripts

# Run
repos
```

### Example 2: Work on multiple branches

```bash
# repos.list
myorg/main-project
@feature-a
@feature-b
@bugfix-123

# Run
repos

# Now you have:
# - myorg/main-project (main branch)
# - main-project-feature-a (feature-a worktree)
# - main-project-feature-b (feature-b worktree)
# - main-project-bugfix-123 (bugfix-123 worktree)
```

### Example 3: Mixed repositories and worktrees

```bash
# repos.list
company/backend
company/frontend@develop
@staging
company/docs
@preview

# This creates:
# - backend/ (full clone)
# - frontend-develop/ (develop branch only)
# - backend-staging/ (worktree from backend)
# - docs/ (full clone)
# - docs-preview/ (worktree from docs)
```

## Troubleshooting

### Authentication Errors

If you see "could not read Username" errors:

```bash
export GH_TOKEN="your_token"
# or
gh auth login
```

### Permission Issues

After installation, if `/usr/bin/repos` is not executable:

```bash
sudo chmod +x /usr/bin/repos
```

### Missing Dependencies

```bash
sudo apt-get install bash git curl jq
```

## Uninstallation

```bash
sudo dpkg -r repos
```

## License

MIT License - see debian/copyright for details

## Contributing

Issues and pull requests welcome at https://github.com/MiguelRodo/repos

## Author

Miguel Rodo <miguel.rodo@uct.ac.za>
