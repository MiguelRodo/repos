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


USAGE = """\
Usage: repos <command> [options]

Commands:
  clone       Clone repositories listed in repos.list into the parent directory
  workspace   Generate (or update) the VS Code multi-root workspace file
  codespace   Configure GitHub Codespaces authentication
  codespaces  Alias for codespace
  run         Execute a script inside each cloned repository

Run 'repos <command> --help' for more information on a command.
"""

SUBCOMMAND_SCRIPTS = {
    "clone":      "helper/clone-repos.sh",
    "workspace":  "helper/vscode-workspace-add.sh",
    "codespace":  "helper/codespaces-auth-add.sh",
    "codespaces": "helper/codespaces-auth-add.sh",
    "run":        "run-pipeline.sh",
}


def main():
    """
    Main entry point for the repos CLI command.
    
    This function is registered as a console script entry point,
    allowing users to run 'repos' from the command line after installation.

    Supports subcommands:
      repos clone [flags]      — delegates to clone-repos.sh
      repos workspace [flags]  — delegates to vscode-workspace-add.sh
      repos codespace [flags]  — delegates to codespaces-auth-add.sh
      repos codespaces [flags] — alias for codespace
      repos run [flags]        — delegates to run-pipeline.sh
    """
    args = sys.argv[1:]

    # No arguments or help flag → print usage
    if not args or args[0] in ("-h", "--help"):
        print(USAGE, end="")
        sys.exit(0 if args else 1)

    subcommand = args[0]
    remaining = args[1:]

    if subcommand not in SUBCOMMAND_SCRIPTS:
        print(f"Error: unknown command '{subcommand}'\n", file=sys.stderr)
        print(USAGE, end="", file=sys.stderr)
        sys.exit(1)

    script = SUBCOMMAND_SCRIPTS[subcommand]

    try:
        run_script(script, remaining)
        sys.exit(0)
    except subprocess.CalledProcessError as e:
        sys.exit(e.returncode)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
