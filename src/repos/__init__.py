"""
repos - Multi-Repository Management Tool

A Python wrapper for the repos Bash scripts that manage multiple related Git repositories.
"""

import os
import sys
import subprocess
from pathlib import Path
from typing import Optional, List, Union

__version__ = "1.1.0"

# Version of the repos CLI bundled inside this package.
# Updated automatically by the version-and-release workflow.
_BUNDLED_CLI_VERSION = "1.3.3"


def bundled_cli_version() -> str:
    """
    Return the version of the repos CLI bundled inside this package.

    The Python package ships its own copy of the Bash scripts at a specific
    CLI version.  This function returns that pinned version string.

    Returns:
        str: The bundled CLI version (e.g. ``"1.1.0"``).

    Examples:
        >>> from repos import bundled_cli_version
        >>> bundled_cli_version()
        '1.1.0'
    """
    return _BUNDLED_CLI_VERSION


def installed_cli_version() -> Optional[str]:
    """
    Return the version of the repos CLI installed on the system PATH, or None.

    Runs ``repos --version`` using the system-wide ``repos`` binary.  If no
    system-wide ``repos`` CLI is found, returns ``None`` instead of raising an
    exception.

    Returns:
        str or None: The installed CLI version string, or ``None`` if not found.

    Examples:
        >>> from repos import installed_cli_version
        >>> ver = installed_cli_version()
        >>> print(ver)   # e.g. "1.1.0" or None
    """
    import shutil
    if shutil.which("repos") is None:
        return None
    try:
        result = subprocess.run(
            ["repos", "--version"],
            capture_output=True,
            text=True,
            check=False,
        )
        output = result.stdout.strip() or result.stderr.strip()
        # Strip a leading "v" if present (e.g. "v1.1.0" → "1.1.0")
        return output.lstrip("v") if output else None
    except Exception:
        return None


def install_cli(run: bool = False) -> None:
    """
    Print OS-appropriate instructions for installing the repos CLI globally.

    The Python package uses its own bundled copy of the CLI for all Python
    functions (``run()``, ``workspace()``, etc.).  However, if you also want
    to use ``repos`` directly from your terminal, you need to install the CLI
    system-wide.  This function prints the recommended installation command for
    your platform and, when *run* is ``True``, also executes it.

    Args:
        run (bool): If ``True``, attempt to run the installer automatically
            (Linux and macOS only; ignored on Windows).  Default is ``False``.

    Returns:
        None

    Examples:
        >>> from repos import install_cli
        >>> # Print installation instructions for your OS
        >>> install_cli()

        >>> # Print instructions AND run the installer
        >>> install_cli(run=True)
    """
    import platform
    import shutil

    system = platform.system()

    if system == "Linux":
        print("To install the repos CLI on Ubuntu/Debian, choose one of:\n")
        print("  # Option 1: APT repository (recommended — keeps repos up to date):")
        print("  curl -fsSL https://raw.githubusercontent.com/MiguelRodo/apt-miguelrodo/main/KEY.gpg \\")
        print("     | sudo gpg --dearmor -o /usr/share/keyrings/miguelrodo-repos.gpg")
        print('  echo "deb [signed-by=/usr/share/keyrings/miguelrodo-repos.gpg] '
              'https://raw.githubusercontent.com/MiguelRodo/apt-miguelrodo/main/ ./" \\')
        print("     | sudo tee /etc/apt/sources.list.d/miguelrodo-repos.list >/dev/null")
        print("  sudo apt-get update && sudo apt-get install -y repos\n")
        print("  # Option 2: User-level install (no sudo required):")
        print("  git clone https://github.com/MiguelRodo/repos.git /tmp/repos-cli")
        print("  bash /tmp/repos-cli/install-local.sh\n")
        if run:
            print("Running user-level installer...")
            import tempfile
            tmp = os.path.join(tempfile.mkdtemp(), "repos-cli")
            ret = subprocess.run(
                f"git clone https://github.com/MiguelRodo/repos.git {tmp!r}"
                f" && bash {os.path.join(tmp, 'install-local.sh')!r}",
                shell=True,
            ).returncode
            if ret != 0:
                print(
                    f"Warning: installer exited with status {ret}."
                    " Check the output above for details.",
                    file=sys.stderr,
                )
    elif system == "Darwin":
        print("To install the repos CLI on macOS, run:\n")
        print("  brew tap MiguelRodo/repos")
        print("  brew install repos\n")
        if run:
            print("Running Homebrew installer...")
            ret = subprocess.run(
                "brew tap MiguelRodo/repos && brew install repos", shell=True
            ).returncode
            if ret != 0:
                print(
                    f"Warning: installer exited with status {ret}."
                    " Check the output above for details.",
                    file=sys.stderr,
                )
    elif system == "Windows":
        print("To install the repos CLI on Windows, run in PowerShell:\n")
        print("  scoop bucket add repos https://github.com/MiguelRodo/scoop-bucket")
        print("  scoop install repos\n")
        print("Or download and run install.ps1 from the releases page:")
        print("  https://github.com/MiguelRodo/repos/releases\n")
        print("(Automatic installation via run=True is not supported on Windows.)")
    else:
        print("To install the repos CLI, see the installation guide:")
        print("  https://miguelrodo.github.io/repos/install.html\n")


def get_script_path(script_name="run-pipeline.sh"):
    """
    Find the path to a repos script.
    
    Args:
        script_name: Name of the script file (e.g., "helper/clone-repos.sh")
        
    Returns:
        Path to the script file
        
    Raises:
        FileNotFoundError: If the script cannot be found
    """
    # Try to find the script using importlib.resources (Python 3.7+)
    try:
        if sys.version_info >= (3, 9):
            from importlib.resources import files
            script_path = files('repos').joinpath('scripts', script_name)
            if script_path.is_file():
                return str(script_path)
        else:
            # Fallback for Python 3.7-3.8
            import importlib.resources as pkg_resources
            with pkg_resources.path('repos.scripts', script_name) as p:
                if p.is_file():
                    return str(p)
    except (ImportError, FileNotFoundError, AttributeError):
        pass
    
    # Fallback: use __file__ relative path
    module_dir = Path(__file__).parent
    script_path = module_dir / 'scripts' / script_name
    
    if script_path.is_file():
        return str(script_path)
    
    raise FileNotFoundError(
        f"Cannot find {script_name}. Make sure the package is properly installed."
    )


def run_script(script_name="run-pipeline.sh", args=None):
    """
    Run a repos script with the given arguments.
    
    Args:
        script_name: Name of the script to run (e.g., "helper/clone-repos.sh")
        args: List of arguments to pass to the script
        
    Returns:
        subprocess.CompletedProcess object
        
    Raises:
        FileNotFoundError: If the script cannot be found
        subprocess.CalledProcessError: If the script exits with non-zero status
        PermissionError: If the script cannot be made executable
    """
    script_path = get_script_path(script_name)
    
    # Ensure the script is executable (may fail in restricted environments)
    try:
        os.chmod(script_path, 0o755)
    except (OSError, PermissionError) as e:
        # If we can't change permissions, try to run anyway
        # (the script may already be executable)
        pass
    
    # Prepare command
    cmd = [script_path]
    if args:
        cmd.extend(args)
    
    # Run the script
    result = subprocess.run(
        cmd,
        check=True,
        text=True
    )
    
    return result


def workspace(
    file: Optional[str] = None,
    debug: bool = False,
    debug_file: Optional[Union[bool, str]] = None,
    **kwargs
):
    """
    Generate or update the VS Code multi-root workspace file.

    Args:
        file: Path to repos list file (default: repos.list)
        debug: If True, enable debug output to stderr
        debug_file: Enable debug output to file (auto-generated if True, or specify path)
        **kwargs: Additional keyword arguments (captured but ignored, for extensibility)

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> # Generate workspace from default repos.list
        >>> workspace()

        >>> # Use a different file
        >>> workspace(file="my-repos.list")
    """
    script_args = []

    if file is not None:
        script_args.extend(["-f", file])

    if debug:
        script_args.append("--debug")

    if debug_file is not None:
        if debug_file is True:
            script_args.append("--debug-file")
        else:
            script_args.extend(["--debug-file", debug_file])

    return run_script("helper/vscode-workspace-add.sh", script_args)


def workspace_raw(*args):
    """
    Generate or update the VS Code workspace file (raw argument passing).

    Args:
        *args: Command-line arguments to pass directly to vscode-workspace-add.sh

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> workspace_raw("-f", "custom.list")
    """
    return run_script("helper/vscode-workspace-add.sh", list(args))


def codespace(
    file: Optional[str] = None,
    devcontainer: Optional[Union[str, List[str]]] = None,
    permissions: Optional[str] = None,
    tool: Optional[str] = None,
    debug: bool = False,
    debug_file: Optional[Union[bool, str]] = None,
    **kwargs
):
    """
    Configure GitHub Codespaces authentication.

    Injects the GH_TOKEN Codespaces secret into every cloned repository
    that has a devcontainer.json.

    Args:
        file: Path to repos list file (default: repos.list)
        devcontainer: Path(s) to devcontainer.json file(s)
        permissions: Pass through to codespaces-auth-add.sh ("all" or "contents")
        tool: Force tool for codespaces-auth-add.sh (e.g., "jq", "python")
        debug: If True, enable debug output to stderr
        debug_file: Enable debug output to file (auto-generated if True, or specify path)
        **kwargs: Additional keyword arguments (captured but ignored, for extensibility)

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> # Configure with default devcontainer path
        >>> codespace()

        >>> # Specify devcontainer paths
        >>> codespace(devcontainer=".devcontainer/devcontainer.json")

        >>> # Multiple devcontainer paths
        >>> codespace(devcontainer=[".devcontainer/devcontainer.json",
        ...                         ".devcontainer/prebuild/devcontainer.json"])
    """
    script_args = []

    if file is not None:
        script_args.extend(["-f", file])

    if devcontainer is not None:
        devcontainers = [devcontainer] if isinstance(devcontainer, str) else devcontainer
        for dc in devcontainers:
            script_args.extend(["-d", dc])

    if permissions is not None:
        script_args.extend(["--permissions", permissions])

    if tool is not None:
        script_args.extend(["-t", tool])

    if debug:
        script_args.append("--debug")

    if debug_file is not None:
        if debug_file is True:
            script_args.append("--debug-file")
        else:
            script_args.extend(["--debug-file", debug_file])

    return run_script("helper/codespaces-auth-add.sh", script_args)


def codespace_raw(*args):
    """
    Configure GitHub Codespaces authentication (raw argument passing).

    Args:
        *args: Command-line arguments to pass directly to codespaces-auth-add.sh

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> codespace_raw("-d", ".devcontainer/devcontainer.json")
    """
    return run_script("helper/codespaces-auth-add.sh", list(args))


def run(
    file: Optional[str] = None,
    script: Optional[str] = None,
    include: Optional[Union[str, List[str]]] = None,
    exclude: Optional[Union[str, List[str]]] = None,
    ensure_setup: bool = False,
    skip_deps: bool = False,
    dry_run: bool = False,
    verbose: bool = False,
    continue_on_error: bool = False,
    **kwargs
):
    """
    Execute a script inside each cloned repository.
    
    Args:
        file: Path to repos list file (default: repos.list)
        script: Script to run in each repo, relative to repo root (default: run.sh)
        include: Repo name(s) to include (string or list of strings)
        exclude: Repo name(s) to exclude (string or list of strings)
        ensure_setup: If True, clone repositories before executing scripts
        skip_deps: If True, skip the install-r-deps.sh step
        dry_run: If True, show what would be done without executing
        verbose: If True, enable verbose logging
        continue_on_error: If True, continue on failure and report all results
        **kwargs: Additional keyword arguments (captured but ignored, for extensibility)
        
    Returns:
        subprocess.CompletedProcess object
        
    Examples:
        >>> # Run the default script (run.sh) in each repo
        >>> run()
        
        >>> # Run a custom script
        >>> run(script="build.sh")
        
        >>> # Continue past failures
        >>> run(continue_on_error=True)
        
        >>> # Dry-run mode
        >>> run(dry_run=True)
        
        >>> # Include only specific repos
        >>> run(include=["repo1", "repo2"])
        
        >>> # Exclude specific repos
        >>> run(exclude="repo3")
        
        >>> # Multiple options
        >>> run(script="test.sh", verbose=True, ensure_setup=True)
    """
    script_args = []
    
    # Build argument list from keyword parameters
    if file is not None:
        script_args.extend(["-f", file])
    
    if script is not None:
        script_args.extend(["--script", script])
    
    if include is not None:
        include_str = ",".join(include) if isinstance(include, list) else include
        script_args.extend(["-i", include_str])
    
    if exclude is not None:
        exclude_str = ",".join(exclude) if isinstance(exclude, list) else exclude
        script_args.extend(["-e", exclude_str])
    
    if ensure_setup:
        script_args.append("--ensure-setup")
    
    if skip_deps:
        script_args.append("-d")
    
    if dry_run:
        script_args.append("-n")
    
    if verbose:
        script_args.append("-v")
    
    if continue_on_error:
        script_args.append("--continue-on-error")
    
    return run_script("run-pipeline.sh", script_args)


def run_raw(*args):
    """
    Execute a script inside each cloned repository (raw argument passing).
    
    This function provides backward compatibility for passing raw command-line arguments.
    For idiomatic Python usage, use run() with keyword arguments instead.
    
    Args:
        *args: Command-line arguments to pass directly to run-pipeline.sh
        
    Returns:
        subprocess.CompletedProcess object
        
    Examples:
        >>> # Backward compatibility - raw argument passing
        >>> run_raw("--script", "build.sh", "--dry-run")
        >>> run_raw("-f", "custom.list", "--continue-on-error")
    """
    return run_script("run-pipeline.sh", list(args))


def clone(
    file: Optional[str] = None,
    debug: bool = False,
    debug_file: Optional[Union[bool, str]] = None,
    **kwargs
):
    """
    Clone repositories listed in a repos.list file.

    Each non-empty, non-comment line in the list file describes one cloning
    instruction (full repo, specific branch, or worktree branch).  See the
    `repos.list format <https://miguelrodo.github.io/repos/repos-list.html>`_
    for the full syntax.

    Global flags in repos.list (``--worktree``) are automatically applied.

    Args:
        file: Path to repos list file (default: repos.list, or
            repos-to-clone.list if repos.list is absent)
        debug: If True, enable debug tracing to stderr
        debug_file: Enable debug tracing to file (auto-generated if True,
            or specify an explicit path)
        **kwargs: Additional keyword arguments (captured but ignored, for extensibility)

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> clone()
        >>> clone(file="my-repos.list")
        >>> clone(debug=True)
    """
    script_args = []

    if file is not None:
        script_args.extend(["-f", file])

    if debug:
        script_args.append("--debug")

    if debug_file is not None:
        if debug_file is True:
            script_args.append("--debug-file")
        else:
            script_args.extend(["--debug-file", debug_file])

    return run_script("helper/clone-repos.sh", script_args)


def clone_raw(*args):
    """
    Clone repositories listed in a repos.list file (raw argument passing).

    Args:
        *args: Command-line arguments to pass directly to clone-repos.sh

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> clone_raw("-f", "my-repos.list")
        >>> clone_raw("--debug")
    """
    return run_script("helper/clone-repos.sh", list(args))


def add_branch(
    branch_name: str,
    target_dir: Optional[str] = None,
    use_branch: bool = False,
    **kwargs
):
    """
    Create a new worktree/branch off the current repository.

    Creates a new worktree at ``../<repo>-<branch>`` (or ``../<target_dir>``),
    pushes the branch to origin, cleans the worktree, updates devcontainer.json,
    adds the branch to repos.list, and refreshes the VS Code workspace file.

    Args:
        branch_name: Name of the new branch to create
        target_dir: Optional custom directory name (default: <repo>-<branch>)
        use_branch: If True, create as a separate branch instead of worktree
        **kwargs: Additional keyword arguments (captured but ignored, for extensibility)

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> add_branch("data-tidy")
        >>> add_branch("analysis", target_dir="my-analysis")
        >>> add_branch("paper", use_branch=True)
    """
    script_args = [branch_name]

    if target_dir is not None:
        script_args.append(target_dir)

    if use_branch:
        script_args.append("--branch")

    return run_script("add-branch.sh", script_args)


def add_branch_raw(*args):
    """
    Create a new worktree/branch off the current repository (raw argument passing).

    Args:
        *args: Command-line arguments to pass directly to add-branch.sh

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> add_branch_raw("data-tidy")
        >>> add_branch_raw("analysis", "my-analysis")
    """
    return run_script("add-branch.sh", list(args))


def update_branches(
    dry_run: bool = False,
    **kwargs
):
    """
    Update all worktrees with the latest devcontainer prebuild configuration.

    Reads ``.devcontainer/prebuild/devcontainer.json`` from the base repository,
    strips the codespaces repositories section, and writes the result to
    ``.devcontainer/devcontainer.json`` in each worktree, then commits and pushes.

    Args:
        dry_run: If True, show what would be done without making changes
        **kwargs: Additional keyword arguments (captured but ignored, for extensibility)

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> update_branches()
        >>> update_branches(dry_run=True)
    """
    script_args = []

    if dry_run:
        script_args.append("--dry-run")

    return run_script("update-branches.sh", script_args)


def update_branches_raw(*args):
    """
    Update all worktrees with the latest devcontainer prebuild configuration (raw argument passing).

    Args:
        *args: Command-line arguments to pass directly to update-branches.sh

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> update_branches_raw("--dry-run")
    """
    return run_script("update-branches.sh", list(args))


def update_scripts(
    branch: Optional[str] = None,
    dry_run: bool = False,
    force: bool = False,
    **kwargs
):
    """
    Update scripts from the upstream CompTemplate repository.

    Clones/pulls the latest ``MiguelRodo/CompTemplate`` repository and copies
    all scripts from its ``scripts/`` directory (including ``helper/``) into
    the local scripts directory, then creates a commit with the updates.

    Args:
        branch: Upstream branch to pull from (default: main)
        dry_run: If True, show what would be updated without making changes
        force: If True, overwrite local changes without prompting
        **kwargs: Additional keyword arguments (captured but ignored, for extensibility)

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> update_scripts()
        >>> update_scripts(branch="dev")
        >>> update_scripts(dry_run=True)
        >>> update_scripts(force=True)
    """
    script_args = []

    if branch is not None:
        script_args.extend(["--branch", branch])

    if dry_run:
        script_args.append("--dry-run")

    if force:
        script_args.append("--force")

    return run_script("update-scripts.sh", script_args)


def update_scripts_raw(*args):
    """
    Update scripts from the upstream CompTemplate repository (raw argument passing).

    Args:
        *args: Command-line arguments to pass directly to update-scripts.sh

    Returns:
        subprocess.CompletedProcess object

    Examples:
        >>> update_scripts_raw("--branch", "dev", "--dry-run")
    """
    return run_script("update-scripts.sh", list(args))
