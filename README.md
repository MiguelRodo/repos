# CompTemplate

This repository provides infrastructure for multi-repository R-based computational research projects with containerized development environments.

## Table of Contents

- [Quick Start](#quick-start)
- [What This Template Provides](#what-this-template-provides)
- [Working with Repositories](#working-with-repositories)
- [Running the Pipeline](#running-the-pipeline)
- [Managing Worktrees](#managing-worktrees)
- [Devcontainer Setup](#devcontainer-setup)
- [Troubleshooting](#troubleshooting)
- [For Template Maintainers](#for-template-maintainers)

## Quick Start

### Clone and Setup Everything

Copy and paste this command block to clone this repository and set up all sub-repositories:

```bash
# Clone the CompTemplate repository
git clone https://github.com/MiguelRodo/CompTemplate.git
cd CompTemplate

# Edit repos.list to specify your repositories
# (Open repos.list and add your repo specifications)

# Run the setup script - creates repos, clones them, and configures workspace
scripts/setup-repos.sh
```

That's it! The `setup-repos.sh` script will:
1. Create any missing repositories on GitHub
2. Clone all specified repositories to the parent directory
3. Generate a VS Code workspace file
4. Configure Codespaces authentication

### For Existing Projects

If the repositories are already set up and you just want to clone them:

```bash
git clone https://github.com/YOUR-ORG/YourProject.git
cd YourProject
scripts/helper/clone-repos.sh
```

## What This Template Provides

**Multi-Repository Management**: Easily work with multiple related Git repositories as a unified project.

**Containerized R Environment**: Ready-to-use devcontainer with:
- Bioconductor (RELEASE_3_20 by default)
- Quarto with TinyTeX
- radian (modern R console)
- Pre-installed R packages (via renv)

**Automated Scripts**:
- `scripts/setup-repos.sh` - Complete project setup
- `scripts/run-pipeline.sh` - Execute analysis pipeline
- `scripts/add-branch.sh` - Create worktrees for parallel development
- `scripts/update-branches.sh` - Sync devcontainer across worktrees
- `scripts/update-scripts.sh` - Pull latest scripts from CompTemplate

**GitHub Actions**: Automated devcontainer builds pushed to GitHub Container Registry.

## Working with Repositories

### Understanding repos.list

The `repos.list` file specifies which repositories to include. Format:

```bash
# Clone full repository
owner/repo

# Clone specific branch
owner/repo@branch

# Create worktree from current repo
@branch-name [target-directory]

# Clone with custom directory name
owner/repo custom-name
```

**Examples:**
```bash
# Worktrees off the current repo (CompTemplate)
@data-tidy
@analysis analysis-folder

# External repositories
SATVILab/projr
SATVILab/UtilsCytoRSV@release

# Worktrees off SATVILab/projr (because it's the last non-@ line)
@dev
@staging
```

### Where Do Repositories Go?

All repositories are cloned to the **parent directory** of CompTemplate:

```
workspaces/
├── CompTemplate/          # This repo (contains repos.list and scripts)
├── CompTemplate-analysis/ # @analysis worktree
├── CompTemplate-paper/    # @paper worktree
├── projr/                 # SATVILab/projr clone
├── projr-dev/             # @dev worktree of projr
└── UtilsCytoRSV/          # SATVILab/UtilsCytoRSV clone
```

### VS Code Workspace

Open all repositories together in VS Code:

```bash
# Generate/update workspace file
scripts/helper/vscode-workspace-add.sh

# Open in VS Code
code entire-project.code-workspace
```

### Other Editors

Without VS Code, simply open each repository directory individually:

```bash
# Navigate to any repository
cd ../projr
# Open in your editor
vim .  # or emacs, RStudio, etc.
```

## Running the Pipeline

The `run-pipeline.sh` script executes your analysis across all repositories.

### Quick Run

<details>
<summary><b>From Bash</b></summary>

```bash
cd CompTemplate
scripts/run-pipeline.sh
```

Options:
- `-s, --skip-setup` - Skip repository setup
- `-d, --skip-deps` - Skip R dependency installation
- `-i, --include <names>` - Only run specific repositories
- `-e, --exclude <names>` - Exclude specific repositories
- `-n, --dry-run` - Show what would run without executing
- `-v, --verbose` - Enable detailed logging

Examples:
```bash
# Run only specific repos
scripts/run-pipeline.sh --include "projr,UtilsCytoRSV"

# Skip setup if repos are already cloned
scripts/run-pipeline.sh --skip-setup

# Preview without executing
scripts/run-pipeline.sh --dry-run
```

</details>

<details>
<summary><b>From R</b></summary>

```r
# Set working directory to CompTemplate
setwd("path/to/CompTemplate")

# Run the pipeline
system2("scripts/run-pipeline.sh")

# With options
system2("scripts/run-pipeline.sh", args = c("--skip-setup", "--verbose"))

# On Windows, you may need to use bash explicitly
system2("bash", args = c("scripts/run-pipeline.sh"))
```

</details>

<details>
<summary><b>From Python</b></summary>

```python
import subprocess
import os

# Set working directory to CompTemplate
os.chdir('path/to/CompTemplate')

# Run the pipeline
subprocess.run(['scripts/run-pipeline.sh'])

# With options
subprocess.run([
    'scripts/run-pipeline.sh',
    '--skip-setup',
    '--verbose'
])

# On Windows
subprocess.run(['bash', 'scripts/run-pipeline.sh'])
```

</details>

### What run-pipeline.sh Does

1. **Setup** (unless `--skip-setup`):
   - Runs `scripts/setup-repos.sh`
   - Creates missing repos
   - Clones repositories
   - Updates workspace

2. **Dependencies** (unless `--skip-deps`):
   - Runs `scripts/helper/install-r-deps.sh`
   - Installs R packages from `renv.lock` or `DESCRIPTION`

3. **Execute**:
   - Runs `run.sh` in each repository (if present)
   - Stops on first failure

### Creating run.sh in Your Repositories

Each repository can have a `run.sh` script that `run-pipeline.sh` will execute:

```bash
#!/usr/bin/env bash
# run.sh - Execute repository-specific analysis

set -e

echo "Running analysis for $(basename $(pwd))"

# Example: Run R script
Rscript analysis/main.R

# Example: Render Quarto document
quarto render analysis/report.qmd

echo "Analysis complete"
```

Make it executable:
```bash
chmod +x run.sh
```

## Managing Worktrees

Worktrees let you work on multiple branches simultaneously without cloning the entire repository multiple times.

### Create a New Worktree

```bash
# From the CompTemplate directory
scripts/add-branch.sh <branch-name> [target-directory]

# Examples
scripts/add-branch.sh data-tidy           # Creates ../CompTemplate-data-tidy
scripts/add-branch.sh analysis my-folder  # Creates ../my-folder
```

This creates a worktree with:
- Minimal infrastructure (only `.devcontainer/` and `.gitignore`)
- Ready-to-use devcontainer from prebuild
- Automatically added to `repos.list` and workspace

### Update All Worktrees

After updating the devcontainer configuration:

```bash
scripts/update-branches.sh

# Preview changes
scripts/update-branches.sh --dry-run
```

### Remove a Worktree

Always use `git worktree remove` to properly remove worktrees:

```bash
# Correct way: Remove the worktree using git
git worktree remove ../CompTemplate-data-tidy

# Remove from repos.list manually
# Remove from workspace
scripts/helper/vscode-workspace-add.sh
```

**Important**: If you manually delete a worktree directory (e.g., `rm -rf ../worktree-name`), git will have a stale reference that prevents re-adding that branch. The setup scripts now automatically prune stale worktree references, but it's best to use `git worktree remove` to avoid this issue.

If you encounter stale worktree errors, you can manually prune them:

```bash
# Clean up stale worktree references
git worktree prune

# Or if you need to force-remove a specific worktree
git worktree remove --force ../CompTemplate-data-tidy
```

## Devcontainer Setup

### Base Configuration

The devcontainer uses Bioconductor by default:

```dockerfile
FROM bioconductor/bioconductor_docker:RELEASE_3_20
```

To change the base image, edit `.devcontainer/Dockerfile`.

### Features Included

- **Quarto** with TinyTeX
- **radian** (modern R console)
- **Common Ubuntu packages** for R/data science
- **repos feature**: Auto-clones repositories in Codespaces
- **config-r feature**: Pre-installs R packages from lockfiles

### Pre-installing R Packages

Place `renv.lock` files in `.devcontainer/renv/<project>/` to pre-install packages during container build:

```
.devcontainer/
└── renv/
    ├── project1/
    │   └── renv.lock
    └── project2/
        └── renv.lock
```

### Automated Builds

GitHub Actions automatically builds and pushes devcontainer images:
- Triggered on push to `main` branch
- Images pushed to `ghcr.io`
- Pre-built reference in `.devcontainer/prebuild/devcontainer.json`

To disable: Remove the `on.push` section in `.github/workflows/devcontainer-build.yml`.

### Using in Codespaces

**Authentication Required**: The setup scripts run in non-interactive mode and require GitHub credentials to clone and push to repositories.

1. **Set up GitHub Token** (Required):
   - Go to [Codespaces secrets settings](https://github.com/settings/codespaces)
   - Add `GH_TOKEN` as a Codespaces secret with your personal access token
   - Token needs permissions to clone/push to your specified repositories

2. **Token Permissions**: Your token should have:
   - `repo` scope for private repositories
   - `public_repo` scope for public repositories

3. Codespaces will automatically use the pre-built image

**Alternative Authentication Methods**:
- **SSH**: Configure SSH keys in your Codespaces settings for git@github.com URLs
- **gh CLI**: The `gh auth login` command (automatically configured in Codespaces)

**For CI/CD environments**: The setup scripts will check for authentication and fail early with a helpful error message if credentials are not available.

### Dotfiles Configuration

For additional container customization (e.g., radian settings):

```bash
git clone https://github.com/SATVILab/dotfiles.git "$HOME"/dotfiles
"$HOME"/dotfiles/install-env.sh dev
```

## Troubleshooting

### Authentication Errors

If you see errors like `could not read Username for 'https://github.com': terminal prompts disabled`, the scripts are running in non-interactive mode without credentials.

**Solution**:
1. Set `GH_TOKEN` environment variable:
   ```bash
   export GH_TOKEN="your_github_personal_access_token"
   ```

2. For Codespaces: Add `GH_TOKEN` as a repository or user secret in [Codespaces settings](https://github.com/settings/codespaces)

3. Alternative: Use SSH URLs and configure SSH keys, or authenticate with `gh auth login`

### Stale Worktree Errors

If you see `fatal: 'branch-name' is already checked out at 'path/to/deleted/worktree'`:

**Cause**: You manually deleted a worktree directory (e.g., `rm -rf`) instead of using `git worktree remove`.

**Solution**: The setup scripts now automatically prune stale worktrees, but you can manually fix it:
```bash
# Prune stale worktree references
git worktree prune

# Verify the stale reference is gone
git worktree list
```

**Prevention**: Always use `git worktree remove` to properly remove worktrees:
```bash
git worktree remove ../worktree-directory
```

### Clone/Push Failures

If cloning or pushing fails:

1. **Check your token permissions**: Ensure your `GH_TOKEN` has `repo` scope for private repos or `public_repo` for public repos

2. **Verify repository access**: Make sure you have access to all repositories listed in `repos.list`

3. **Check network connectivity**: Ensure you can reach github.com

4. **Debug mode**: Run scripts with debug flag to see detailed output:
   ```bash
   scripts/helper/clone-repos.sh --debug
   ```

## For Template Maintainers

### Testing

<details>
<summary><b>Comprehensive Clone Variations Test</b></summary>

```bash
# Run comprehensive test for clone-repos.sh
tests/test-clone-variations-comprehensive.sh

# Tests all clone-repos.sh variations including:
# - Full repo clones (with/without -a flag, with/without custom target)
# - Single-branch clones (with/without custom target)
# - Worktrees (with/without custom target, with/without --no-worktree flag)
# - Fallback repo tracking across multiple clone operations
# - Branch name sanitization (slashes → dashes in directory names)
# - Multiple vs single reference logic (branch suffix behavior)
# - file:// URLs and absolute path support
# - Error handling (non-empty directories)

# Coverage: 16 test scenarios with 32 assertions
```

</details>

<details>
<summary><b>Manual Tests for setup-repos.sh</b></summary>

```bash
# Run manual test suite
tests/test-setup-repos.sh

# Tests include:
# - Repository creation
# - Cloning with various formats
# - Worktree creation
# - Workspace generation
# - Codespaces auth configuration
```

</details>

<details>
<summary><b>Automated Tests for run-pipeline.sh</b></summary>

```bash
# Run automated test suite
tests/test-run-pipeline.sh

# Tests include:
# - Dry-run mode
# - Include/exclude filters
# - Skip setup/deps flags
# - Error handling
```

</details>

### Updating Helper Scripts

Pull the latest scripts from the upstream CompTemplate repository:

```bash
scripts/update-scripts.sh

# From a specific branch
scripts/update-scripts.sh --branch dev

# Preview changes
scripts/update-scripts.sh --dry-run
```

This updates all scripts in `scripts/` directory, including both main scripts and `scripts/helper/` scripts.

### Repository Structure

```
.
├── .devcontainer/
│   ├── devcontainer.json        # Main devcontainer config
│   ├── Dockerfile               # Container definition
│   ├── prebuild/                # Pre-built image reference
│   │   └── devcontainer.json
│   └── renv/                    # R package lockfiles
├── .github/
│   └── workflows/
│       ├── devcontainer-build.yml
│       └── add-issues-to-project.yml
├── scripts/
│   ├── setup-repos.sh           # Main setup orchestrator
│   ├── run-pipeline.sh          # Pipeline executor
│   ├── add-branch.sh            # Create worktrees
│   ├── update-branches.sh       # Update worktree devcontainers
│   ├── update-scripts.sh        # Pull latest scripts from CompTemplate
│   └── helper/                  # Helper scripts (updated from upstream)
│       ├── clone-repos.sh       # ⭐ Canonical path logic
│       ├── vscode-workspace-add.sh
│       ├── codespaces-auth-add.sh
│       ├── create-repos.sh
│       └── install-r-deps.sh
├── tests/
│   ├── test-clone-variations-comprehensive.sh  # Comprehensive clone-repos.sh tests
│   ├── test-setup-repos.sh      # Manual tests
│   └── test-run-pipeline.sh     # Automated tests
├── repos.list                   # Repository specifications
├── entire-project.code-workspace # VS Code workspace
└── README.md

```

### Path Logic

All helper scripts follow `clone-repos.sh` path conventions:

**Key Principles:**
- All repositories are cloned to the **parent directory** of the current directory
- Running from `/workspaces/CompTemplate` → repos go to `/workspaces/`
- Worktrees are named `<repo>-<branch>` unless custom name provided
- Single-branch clones may or may not include branch suffix (depends on reference count)

**Examples:**
```bash
# From /workspaces/CompTemplate

owner/repo           # → /workspaces/repo
owner/repo@branch    # → /workspaces/repo-branch (if multiple refs) or /workspaces/repo
@branch              # → /workspaces/CompTemplate-branch
@branch custom-name  # → /workspaces/custom-name
```

See `.github/copilot-instructions.md` for detailed path resolution documentation.

---

## License

[Specify your license here]

## Contact

For more information, please contact:
- [Name], [Email Address]
- [Name], [Email Address]

## Citation

If you use this template, please cite:
```
[Citation information]
```
