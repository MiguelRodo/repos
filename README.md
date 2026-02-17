# repos - Multi-Repository Management Tool

A command-line tool for managing multiple related Git repositories as a unified workspace.

## Features

- **Multi-Repository Management**: Clone and manage multiple related Git repositories
- **Git Worktrees**: Create and manage Git worktrees for parallel development
- **VS Code Integration**: Generate workspace files for multi-root workspaces
- **Pipeline Execution**: Run scripts across all repositories
- **Simple Configuration**: Define repositories in a simple list file

## Installation

### Ubuntu/Debian

Download and install the latest `.deb` package from the [Releases page](https://github.com/MiguelRodo/repos/releases):

```bash
# Download the latest release (replace VERSION with actual version, e.g., 1.0.0)
wget https://github.com/MiguelRodo/repos/releases/download/vVERSION/repos_VERSION_all.deb

# Install the package
sudo dpkg -i repos_VERSION_all.deb

# If there are dependency issues, run:
sudo apt-get install -f
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

### From Source

```bash
git clone https://github.com/MiguelRodo/repos.git
cd repos
sudo dpkg-buildpackage -us -uc -b
sudo dpkg -i ../repos_*.deb
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
4. Configure authentication for GitHub Codespaces

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

# Show help
repos --help
```

### Advanced Features

The package installs scripts to `/usr/share/repos/scripts/`:

- `setup-repos.sh` - Main setup orchestrator (called by `repos` command)
- `run-pipeline.sh` - Execute pipeline across all repositories
- `add-branch.sh` - Create worktrees for parallel development
- `update-branches.sh` - Sync devcontainer across worktrees
- `update-scripts.sh` - Pull latest scripts from template

You can call these directly if needed:

```bash
/usr/share/repos/scripts/run-pipeline.sh
/usr/share/repos/scripts/add-branch.sh feature-x
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
