# Copilot Instructions for CompTemplate

## Repository Overview

This is a template repository for setting up multi-repository R-based computational research projects with containerized development environments. It provides infrastructure for:

- Managing multiple related repositories as a unified workspace
- Running R/Bioconductor analyses in Docker containers
- Automated devcontainer builds via GitHub Actions
- VS Code workspace configuration across multiple repositories

## Key Technologies

- **Language**: Bash shell scripts, R (for analysis projects using this template)
- **Container**: Docker, VS Code devcontainers
- **Base Image**: Bioconductor Docker (`bioconductor/bioconductor_docker:RELEASE_3_20`)
- **Tools**: Quarto (with TinyTeX), radian (modern R console), renv (R package management)
- **CI/CD**: GitHub Actions for automated container builds

## Repository Structure

```
.
├── .devcontainer/           # Devcontainer configuration
│   ├── devcontainer.json   # VS Code devcontainer settings
│   ├── Dockerfile          # Container image definition
│   ├── prebuild/           # Pre-built image references
│   │   └── devcontainer.json  # Pre-build configuration (optional)
│   └── renv/               # R package lockfiles for pre-installation
├── .github/
│   └── workflows/          # GitHub Actions workflows
│       ├── devcontainer-build.yml    # Automated container builds
│       └── add-issues-to-project.yml # Issue management
├── scripts/                # Main scripts
│   ├── setup-repos.sh      # Main setup orchestrator
│   ├── run-pipeline.sh     # Execute analysis pipeline
│   ├── add-branch.sh       # Create new worktree/branch off current repo
│   ├── update-branches.sh  # Update worktrees with latest devcontainer
│   ├── update-scripts.sh   # Pull latest scripts from MiguelRodo/CompTemplate
│   └── helper/             # Helper scripts (used by main scripts)
│       ├── clone-repos.sh      # Clone repositories (CANONICAL path logic)
│       ├── vscode-workspace-add.sh  # Generate VS Code workspace file
│       ├── codespaces-auth-add.sh   # Configure GitHub auth in Codespaces
│       ├── create-repos.sh     # Create new repositories on GitHub
│       └── install-r-deps.sh   # Install R dependencies
├── tests/                  # Test scripts
│   ├── test-setup-repos.sh     # Manual tests for setup-repos.sh
│   └── test-run-pipeline.sh    # Automated tests for run-pipeline.sh
├── repos.list              # List of repositories to clone (format: owner/repo@branch)
├── entire-project.code-workspace  # VS Code multi-root workspace file
└── README.md               # Documentation
```

## Important Files

### `repos.list`
- Format: `owner/repo` or `owner/repo@branch`
- Specifies repositories to clone for the multi-repository workspace
- Used by `scripts/clone-repos.sh` and devcontainer features

### `.devcontainer/devcontainer.json`
- Configures the development container environment
- Includes custom features for repository cloning and R package pre-installation
- Pre-installs VS Code extensions including GitHub Copilot

### `scripts/clone-repos.sh`
- Clones all repositories specified in `repos.list`
- Works on Linux, macOS, and Windows (via Git Bash)
- **Canonical reference for default path behavior** - all other scripts should follow this

#### Default Path Logic
The script uses sophisticated path resolution for repositories and worktrees:

**Base Directory**: All clones/worktrees are created in the **parent directory** of the current working directory
- If running from `/workspaces/CompTemplate`, repos are cloned to `/workspaces/`

**Path Resolution for Clone Lines** (`owner/repo` or `owner/repo@branch`):
1. **With explicit target**: `owner/repo target_dir` → `../target_dir`
2. **Full clone** (no @branch): `owner/repo` → `../repo`
3. **Single-branch clone** (`owner/repo@branch`):
   - If repo has **multiple references** in repos.list: → `../repo-branch`
   - If repo has **single reference**: → `../repo`

**Path Resolution for Worktree Lines** (`@branch`):
1. **With explicit target**: `@branch target_dir` → `../target_dir`
2. **Without target**: `@branch` → `../<fallback_repo>-branch`

**Fallback Repo Logic**:
- Initially: the **current repository** (the one containing `repos.list`)
- After each clone line: updates to the **newly cloned repository**
- Worktree lines do NOT update the fallback

**Reference Counting**:
- The script does a planning phase to count how many times each remote is referenced
- This determines whether to add `-branch` suffix for single-branch clones
- Multiple references to same repo → branches get suffixed (`repo-branch`)
- Single reference → takes base name (`repo`)

**Examples** (assuming running from `/workspaces/CompTemplate`):
```
# Current repo worktrees
@analysis          → /workspaces/CompTemplate-analysis
@paper paper       → /workspaces/paper

# External repo clone + worktrees
SATVILab/projr     → /workspaces/projr (fallback updates)
@dev               → /workspaces/projr-dev (worktree on projr)
@main              → /workspaces/projr-main (worktree on projr)

# Single-branch clone (multiple refs → suffixed)
SATVILab/projr@v1  → /workspaces/projr-v1
SATVILab/projr@v2  → /workspaces/projr-v2

# Single-branch clone (single ref → no suffix)
SATVILab/other@dev → /workspaces/other
```

### `scripts/helper/vscode-workspace-add.sh`
- Generates/updates `entire-project.code-workspace`
- Requires Python or `jq` utility
- Follows `clone-repos.sh` path logic for determining workspace folder paths

### `scripts/helper/codespaces-auth-add.sh`
- Injects GitHub repository permissions into `.devcontainer/devcontainer.json`
- Follows `clone-repos.sh` fallback repo logic for `@branch` lines
- Requires `jq`, Python, or Rscript for JSON manipulation

### `scripts/setup-repos.sh`
- Main orchestrator script that sets up entire multi-repository workspace
- Calls helper scripts in sequence: create-repos → clone-repos → vscode-workspace-add → codespaces-auth-add

### `scripts/run-pipeline.sh`
- Executes analysis pipeline across all repositories
- Calls `setup-repos.sh` first to ensure environment is ready
- Installs R dependencies and runs `run.sh` in each repository

### `scripts/add-branch.sh`
- Creates new worktrees/branches off the current repository
- Cleans up the new worktree to contain minimal infrastructure
- Moves `.devcontainer/prebuild/devcontainer.json` → `.devcontainer/devcontainer.json`
- Automatically adds new branch to `repos.list` and updates workspace

### `scripts/update-branches.sh`
- Updates all worktrees with latest `.devcontainer/prebuild/devcontainer.json`
- Useful after devcontainer image updates

### `scripts/update-scripts.sh`
- Pulls latest scripts from `github.com/MiguelRodo/CompTemplate/scripts`
- Updates all scripts in the `scripts/` directory (including `scripts/helper/`)

## Workflow

### Setting up a new project from this template:

1. **Edit `repos.list`**: Add repositories needed for the project
2. **Run setup**: Execute `scripts/setup-repos.sh` which:
   - Creates any missing repos on GitHub using `scripts/helper/create-repos.sh`
   - Clones repositories using `scripts/helper/clone-repos.sh`
   - Updates VS Code workspace using `scripts/helper/vscode-workspace-add.sh`
   - Configures Codespaces auth using `scripts/helper/codespaces-auth-add.sh`
3. **Customize devcontainer**: Modify `.devcontainer/Dockerfile` if different base image or packages are needed
4. **Add R dependencies** (optional): Place `renv.lock` files in `.devcontainer/renv/<project>/` for pre-installation

### Running the analysis pipeline:

1. **Run pipeline**: Execute `scripts/run-pipeline.sh` which:
   - Calls `scripts/setup-repos.sh` first to ensure repos are set up
   - Installs R dependencies using `scripts/helper/install-r-deps.sh`
   - Executes `run.sh` in each repository (if present)

### Container builds:
- Triggered automatically on push to `main` branch
- Can also be manually triggered via GitHub Actions
- Images pushed to GitHub Container Registry (ghcr.io)
- Pre-built image reference generated in `.devcontainer/prebuild/devcontainer.json`

## Coding Guidelines

### For Bash Scripts:
- Use `#!/usr/bin/env bash` shebang
- Make scripts executable (`chmod +x`)
- Support cross-platform execution where possible (Linux, macOS, Windows/Git Bash)
- Use proper error handling with `set -e` or explicit checks
- Include helpful usage messages and comments

### For Dockerfile/Devcontainer:
- Keep base image version explicit (e.g., `RELEASE_3_20`)
- Set `DEBIAN_FRONTEND=noninteractive` to avoid prompts
- Set appropriate permissions for copied files
- Document any custom configuration

### For R Projects (using this template):
- Use `renv` for package management
- Place lockfiles in `.devcontainer/renv/<project>/renv.lock` for faster container builds
- Use Quarto for reproducible reports

## Common Tasks

### To change the Bioconductor release:
Update the `FROM` line in `.devcontainer/Dockerfile`, e.g.:
```dockerfile
FROM bioconductor/bioconductor_docker:RELEASE_3_19
```

### To add new repositories to the workspace:
1. Add entries to `repos.list`
2. Run `scripts/clone-repos.sh`
3. Run `scripts/vscode-workspace-add.sh`

### To install additional system packages:
Add to the `apt-packages` feature in `.devcontainer/devcontainer.json`:
```json
"ghcr.io/rocker-org/devcontainer-features/apt-packages:1": {
  "packages": "xvfb,vim,libcurl4-openssl-dev,libsecret-1-dev,jq,your-package"
}
```

## Testing

This repository includes comprehensive test suites:

### Automated Tests
- **`tests/test-run-pipeline.sh`**: Automated test suite for run-pipeline.sh
  - Runs in CI/CD environments
  - Tests dry-run mode, filters, skip flags, error handling
  - All tests currently passing

### Manual Tests
- **`tests/test-setup-repos.sh`**: Manual test suite for setup-repos.sh
  - Validates script existence and executability
  - Checks helper script availability
  - Verifies path logic documentation
  - Tests cross-platform compatibility
  - Validates documentation consistency

### Running Tests
```bash
# Run automated tests (safe to run anytime)
tests/test-run-pipeline.sh

# Run manual validation tests
tests/test-setup-repos.sh
```

### Manual Testing Checklist
For full integration testing:
1. Create a test repos.list with real repositories
2. Run `scripts/setup-repos.sh`
3. Verify repositories are cloned to parent directory
4. Verify workspace file is created
5. Verify devcontainer.json is updated (if it exists)
6. Test on Linux, macOS, and Windows (Git Bash)

## Complete Script Reference

### Main Scripts (scripts/)

**`scripts/setup-repos.sh`**
- Main orchestrator for complete project setup
- Calls helper scripts in sequence:
  1. `create-repos.sh` - Creates repos on GitHub
  2. `clone-repos.sh` - Clones repositories
  3. `vscode-workspace-add.sh` - Updates workspace
  4. `codespaces-auth-add.sh` - Configures auth
- Options: `-f <file>`, `-p` (public repos), `--permissions`, `-t` (force tool)
- Always run from project root

**`scripts/run-pipeline.sh`**
- Executes analysis pipeline across all repositories
- Steps:
  1. Runs `setup-repos.sh` (unless `--skip-setup`)
  2. Installs R dependencies (unless `--skip-deps`)
  3. Executes `run.sh` in each repository
- Options: `-s` (skip setup), `-d` (skip deps), `-i` (include), `-e` (exclude), `-n` (dry-run), `-v` (verbose)
- Uses workspace file to discover repositories
- Follows include/exclude filters

**`scripts/add-branch.sh`**
- Creates worktrees with minimal infrastructure off current repo
- Creates worktree at `../<repo>-<branch>` (or custom directory)
- Cleans worktree (keeps only .devcontainer and .gitignore)
- Moves `.devcontainer/prebuild/devcontainer.json` → `.devcontainer/devcontainer.json`
- Strips codespaces repositories config from devcontainer.json
- Auto-adds `@<branch>` to repos.list
- Auto-updates workspace file
- Usage: `scripts/add-branch.sh <branch-name> [target-dir]`

**`scripts/update-branches.sh`**
- Updates all worktrees with latest devcontainer prebuild
- Reads `.devcontainer/prebuild/devcontainer.json` from base repo
- Strips codespaces repositories section
- Writes to `.devcontainer/devcontainer.json` in each worktree
- Commits and pushes changes
- Options: `-n` (dry-run)
- Requires jq or python3

**`scripts/update-scripts.sh`**
- Pulls latest scripts from MiguelRodo/CompTemplate
- Updates all scripts in `scripts/` directory (including `scripts/helper/`)
- Options: `-b <branch>`, `-n` (dry-run), `-f` (force)
- Creates commit with changes
- Environment: `UPSTREAM_BRANCH` to override default branch

### Helper Scripts (scripts/helper/)

**`scripts/helper/clone-repos.sh`** ⭐ CANONICAL
- The authoritative reference for path logic
- All other scripts should follow its conventions
- Supports:
  - Full clones: `owner/repo`
  - Single-branch clones: `owner/repo@branch`
  - Worktrees: `@branch`
  - Custom directories for any of the above
- Planning phase counts references per repo
- Worktree-by-default for @branch lines
- Options: `-f <file>`, `-d` (debug), `-h` (help)

**`scripts/helper/vscode-workspace-add.sh`**
- Generates/updates `entire-project.code-workspace`
- Follows clone-repos.sh path logic exactly
- Requires jq, Python, or Rscript
- Planning phase matches clone-repos.sh
- Supports fallback repo logic for @branch lines
- Options: `-f <file>`, `-d` (debug)

**`scripts/helper/codespaces-auth-add.sh`**
- Injects GitHub repository permissions into devcontainer.json
- Follows clone-repos.sh fallback repo logic
- Handles @branch lines using current fallback
- Supports `--permissions all|contents|default`
- Requires jq, Python, or Rscript
- JSONC-aware (strips comments, trailing commas)

**`scripts/helper/create-repos.sh`**
- Creates GitHub repositories from repos.list
- Uses GitHub API (no local path logic needed)
- Auto-detects User vs Organization
- Creates branches if specified in format `owner/repo@branch`
- Options: `-f <file>`, `-p` (public), `-h` (help)
- Requires `GH_TOKEN` and `GH_USER` or git credentials

**`scripts/helper/install-r-deps.sh`**
- Installs R dependencies across all repositories
- Uses workspace file to find folders
- Per-folder logic:
  - If `renv.lock`: Uses `UtilsProjrMR::projr_renv_restore_and_update()`
  - If `DESCRIPTION`: Uses `pak::local_install_dev_deps()`
  - Otherwise: Skips
- Requires Rscript and jq

## Path Logic Summary

All scripts follow these conventions (defined by `clone-repos.sh`):

**Base Directory**: Parent of current directory
- Running from `/workspaces/CompTemplate` → repos go to `/workspaces/`

**Clone Lines**:
- `owner/repo` → `../repo`
- `owner/repo target` → `../target`
- `owner/repo@branch` → `../repo-branch` (if multiple refs) or `../repo` (if single ref)

**Worktree Lines**:
- `@branch` → `../<fallback_repo>-branch`
- `@branch target` → `../target`

**Fallback Repo**:
- Initially: current repository (containing repos.list)
- After clone line: updates to that cloned repository
- Worktree lines do NOT update fallback

## Notes

- This repository serves as a template. Users should fork/copy it and customize for their specific project needs.
- GitHub token (`GH_TOKEN`) must be configured as a Codespaces secret for private repository cloning
- The `SATVILab/dotfiles` repository can be used for additional container configuration (especially for radian settings)
- All scripts support Linux, macOS, and Windows (via Git Bash)
- Scripts use `#!/usr/bin/env bash` for maximum portability
- Bash 3.2+ required (compatible with macOS default bash)
