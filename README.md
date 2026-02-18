# repos - Multi-Repository Management Tool

[![Test Installation Methods](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-installation.yml)
[![Test Suite](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml/badge.svg)](https://github.com/MiguelRodo/repos/actions/workflows/test-suite.yml)

A command-line tool for managing multiple related Git repositories as a unified workspace.

## Overview

Many projects consist of multiple repositories. For instance, an analysis project might have one repository for data curation and another for analysis. To facilitate this workflow, you can create a repos.list file that specifies the repositories and their branches, and then run `repos setup` to clone them (creating repositories and branches as needed).

Here's an example repos.list file:

```
myorg/data-curation
myorg/analysis
myorg/documentation
```

Run `repos setup` to clone them, and create them if they do not exist:

```bash
repos setup
```

This creates the following directory structure:

```
workspace/
├── my-project/          # Your main project (contains repos.list)
├── data-curation/       # Cloned from myorg/data-curation
├── analysis/            # Cloned from myorg/analysis
└── documentation/       # Cloned from myorg/documentation
```

### Customizations

#### `repos.list`

- Clone to a specific path, e.g. `myorg/data-curation data` 
- Clone specific branches, e.g. `owner/repo@branch`
- Create worktrees from the current repository using `--worktree`, e.g. `owner/repo@branch --worktree`
- Skip specifying repository in `repos.list`, as previous repo listed or current repo used as default.
  - For example, specifying `@data-curation` in the first line would use the current repository as its repository
  - Alternately, specifying `@dev` in the line after `myorg/analysis` would clone the `dev` branch from `myorg/analysis`
- Create repositories as public using the `--public` flag, e.g. `owner/repo --public`

##### Global Flags in repos.list

You can specify global flags at the start of any line in `repos.list` (with only blank space or comments after the flag):

- `--codespaces` - Enable Codespaces authentication for all repositories
- `--public` - Create all repositories as public by default
- `--private` - Create all repositories as private by default
- `--worktree` - Create all branch clones as worktrees instead of separate clones

Example:
```
--public
--codespaces
myorg/repo1
myorg/repo2
```

##### Per-Line Flags

You can also specify `--public` or `--private` on individual repository lines to override the global setting:

Example:
```
--private             # Default to private
myorg/public-repo --public   # Override: create as public
myorg/private-repo    # Use default: private
```

#### `repos`

- Enable Codespaces authentication with `--codespaces`, e.g. `repos setup --codespaces`
- Specify custom `devcontainer.json` paths with `-d`, e.g. `repos setup -d .devcontainer/prebuild/devcontainer.json`
  - Use multiple `-d` flags to specify multiple `devcontainer.json` files

## Installation

You can install repos as a system package (Ubuntu/Debian, macOS, Windows), from source, or as a language-specific wrapper (R or Python).

### <a name="ubuntu-debian"></a>Ubuntu/Debian

You can install repos from the APT repository, with a downloaded `.deb`, or to your local user directory (no sudo required).

#### Option 1: Local Installation (No sudo required)

Install to your user directory (`~/.local/bin`):

```bash
# Clone the repository
git clone https://github.com/MiguelRodo/repos.git
cd repos

# Run the local installer
bash install-local.sh
```

The installer will:
- Install the `repos` command to `~/.local/bin`
- Install scripts to `~/.local/share/repos/scripts`
- Check if `~/.local/bin` is in your PATH and provide instructions if needed

If `~/.local/bin` is not in your PATH, add this line to your `~/.bashrc` or `~/.profile`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Then reload your configuration:

```bash
source ~/.bashrc
```

Run the repos command:

```bash
repos --help
```

To uninstall:

```bash
bash uninstall-local.sh
```

#### Option 2: Install from APT Repository (Recommended)

Install and update `repos` directly via `apt` from [MiguelRodo/apt-miguelrodo](https://github.com/MiguelRodo/apt-miguelrodo):

```bash
# Add repository signing key
curl -fsSL https://raw.githubusercontent.com/MiguelRodo/apt-miguelrodo/main/KEY.gpg \
   | sudo gpg --dearmor -o /usr/share/keyrings/miguelrodo-repos.gpg

# Add apt source
echo "deb [signed-by=/usr/share/keyrings/miguelrodo-repos.gpg] https://raw.githubusercontent.com/MiguelRodo/apt-miguelrodo/main/ ./" \
   | sudo tee /etc/apt/sources.list.d/miguelrodo-repos.list >/dev/null

# Install repos
sudo apt-get update
sudo apt-get install -y repos
```

Run the repos command:

```bash
repos --help
```

To uninstall:

```bash
sudo apt-get remove repos
```

#### Option 3: System-wide Installation from Release .deb (Requires sudo)

Install the .deb package to use the repos command system-wide.

Download and install the latest `.deb` package from the [Releases page](https://github.com/MiguelRodo/repos/releases):

```bash
# Download the latest release (replace VERSION_REPOS with desired version; we try to ensure this is the latest one)
VERSION_REPOS=1.1.0
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
repos --help
```

To uninstall:

```bash
sudo dpkg -r repos
```

#### Dependencies

All installation methods require:
- `bash` - Shell interpreter
- `git` - Version control
- `curl` - HTTP client
- `jq` - JSON processor

These are typically pre-installed on Ubuntu/Debian systems. If not, install them:

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
repos --help
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
repos --help
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
repos --help
```

The formula automatically handles the `jq` dependency. Git is typically pre-installed on macOS.

### <a name="from-source"></a>From Source

Install from source to use the repos command or run scripts directly.

```bash
git clone https://github.com/MiguelRodo/repos.git
cd repos

# For Ubuntu/Debian - Local installation (no sudo)
bash install-local.sh

# For Ubuntu/Debian - System-wide installation (requires sudo)
sudo dpkg-buildpackage -us -uc -b
sudo dpkg -i ../repos_*.deb

# For other systems, use the scripts directly
./scripts/setup-repos.sh
```

Run the repos command:

```bash
repos --help
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

# Use the repos functions with idiomatic R syntax
library(repos)

# Setup repositories
repos_setup()                              # Setup with defaults
repos_setup(file = "my-repos.list")        # Use a different file
repos_setup(public = TRUE)                 # Create repos as public
repos_setup(public = TRUE, codespaces = TRUE)  # Multiple options

# Run pipeline in each repo
repos_run()                                # Run with defaults
repos_run(script = "build.sh")             # Run custom script
repos_run(dry_run = TRUE, verbose = TRUE)  # Dry run with verbose output
repos_run(include = c("repo1", "repo2"))   # Run only in specific repos

# Or use the general repos function
repos("setup", public = TRUE)
repos("run", script = "build.sh")

# Backward compatibility - old syntax still works
repos_setup("--public")
repos_run("--script", "build.sh")
```

Run the repos command:

```r
library(repos)
repos_setup()
```

**System Requirements:** The R package requires `bash`, `git`, `curl`, and `jq` to be installed on your system.

**How it works:** The R package bundles the Bash scripts in `inst/scripts/` and provides wrapper functions that locate and execute them using `system2()`.

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
repos setup                    # Run with default repos.list
repos setup -f my-repos.list
repos setup --public
repos run
repos --help
```

Run the repos command:

```bash
repos --help
```

**System Requirements:** The Python package requires `bash`, `git`, `curl`, and `jq` to be installed on your system. On Windows, you need [Git for Windows](https://git-scm.com/download/win) (which includes Git Bash) or WSL (Windows Subsystem for Linux).

**How it works:** The Python package bundles the Bash scripts in `src/repos/scripts/` and provides both a CLI entry point and a Python API using `subprocess.run()`.

**Python API:**

```python
# Idiomatic Python syntax (recommended)
from repos import setup, run

# Setup repositories
setup()                              # Setup with defaults
setup(file="my-repos.list")          # Use a different file
setup(public=True)                   # Create repos as public
setup(public=True, codespaces=True)  # Multiple options

# Run pipeline in each repo
run()                                # Run with defaults
run(script="build.sh")               # Run custom script
run(dry_run=True, verbose=True)      # Dry run with verbose output
run(include=["repo1", "repo2"])      # Run only in specific repos

# Backward compatibility - raw argument passing
from repos import setup_raw, run_raw

setup_raw("--public")
run_raw("--script", "build.sh")

# Low-level API (if needed)
from repos import run_script
run_script("setup-repos.sh", ["-f", "my-repos.list"])
run_script("run-pipeline.sh")
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
repos setup
```

This will:
1. Create any missing repositories on GitHub (if you have permissions)
2. Clone all specified repositories to the parent directory
3. Generate a VS Code workspace file

To also configure authentication for GitHub Codespaces, use the `--codespaces` flag or specify devcontainer paths with `-d`:

```bash
# Enable Codespaces authentication with default path
repos setup --codespaces

# Specify custom devcontainer.json paths
repos setup -d .devcontainer/devcontainer.json
repos setup -d path1/devcontainer.json -d path2/devcontainer.json
```

## Usage

### Subcommands

The `repos` CLI uses subcommands:

```bash
repos setup [flags]   # Clone and configure repositories
repos run [flags]     # Execute a script in each repository
repos --help          # Show available subcommands
```

### repos setup

Set up repositories from a `repos.list` file:

```bash
# Setup repositories from repos.list
repos setup

# Use a different file
repos setup -f my-repos.list

# Create repositories as public (default is private)
repos setup --public

# Enable Codespaces authentication
repos setup --codespaces

# Specify custom devcontainer.json paths
repos setup -d .devcontainer/devcontainer.json

# Show help
repos setup --help
```

### repos run

Execute a script inside each cloned repository:

```bash
# Run the default script (run.sh) in each repository
repos run

# Run a custom script in each repository
repos run --script pipeline.sh

# Use an alternative list file (concise format)
repos run -f repos-test.list

# Include/exclude specific repos
repos run --include "backend,frontend"
repos run --exclude "docs"

# Continue past failures and report all results
repos run --continue-on-error

# Dry-run mode
repos run --dry-run

# Force setup step before running
repos run --ensure-setup

# Show help
repos run --help
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
repos run

# With options
repos run --include "backend,frontend"
repos run --dry-run
repos run --script pipeline.sh
repos run --continue-on-error
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

After running `repos setup`, open the generated workspace:

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
repos setup
```

### Example 2: Work on multiple branches

```bash
# repos.list
myorg/main-project
@feature-a
@feature-b
@bugfix-123

# Run
repos setup

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

### Local Installation

```bash
bash uninstall-local.sh
```

### System-wide Installation

```bash
sudo dpkg -r repos
```

## License

MIT License - see debian/copyright for details

## Contributing

Issues and pull requests welcome at https://github.com/MiguelRodo/repos

## Author

Miguel Rodo <miguel.rodo@uct.ac.za>
