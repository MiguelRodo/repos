"""
repos - Multi-Repository Management Tool

A Python wrapper for the repos Bash scripts that manage multiple related Git repositories.
"""

import os
import sys
import subprocess
from pathlib import Path
from typing import Optional, List, Union

__version__ = "1.0.0"

def get_script_path(script_name="setup-repos.sh"):
    """
    Find the path to a repos script.
    
    Args:
        script_name: Name of the script file (default: setup-repos.sh)
        
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


def run_script(script_name="setup-repos.sh", args=None):
    """
    Run a repos script with the given arguments.
    
    Args:
        script_name: Name of the script to run (default: setup-repos.sh)
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


def setup(
    file: Optional[str] = None,
    public: bool = False,
    codespaces: bool = False,
    devcontainer: Optional[Union[str, List[str]]] = None,
    permissions: Optional[str] = None,
    tool: Optional[str] = None,
    debug: bool = False,
    debug_file: Optional[Union[bool, str]] = None,
    *args
):
    """
    Clone and configure repositories from a repos.list file.
    
    Args:
        file: Path to repos list file (default: repos.list)
        public: If True, create repositories as public (default is private)
        codespaces: If True, enable Codespaces authentication
        devcontainer: Path(s) to devcontainer.json file(s) (implies codespaces=True)
        permissions: Pass through to codespaces-auth-add.sh ("all" or "contents")
        tool: Force tool for codespaces-auth-add.sh (e.g., "jq", "python")
        debug: If True, enable debug output to stderr
        debug_file: Enable debug output to file (auto-generated if True, or specify path)
        *args: Additional arguments passed directly to setup-repos.sh for backward compatibility
        
    Returns:
        subprocess.CompletedProcess object
        
    Examples:
        >>> # Setup repositories from default repos.list
        >>> setup()
        
        >>> # Use a different file
        >>> setup(file="my-repos.list")
        
        >>> # Create repositories as public
        >>> setup(public=True)
        
        >>> # Enable codespaces authentication
        >>> setup(codespaces=True)
        
        >>> # Multiple options
        >>> setup(public=True, codespaces=True, debug=True)
        
        >>> # Backward compatibility - still works
        >>> setup("--public", "--codespaces")
    """
    script_args = []
    
    # Build argument list from keyword parameters
    if file is not None:
        script_args.extend(["-f", file])
    
    if public:
        script_args.append("--public")
    
    if codespaces:
        script_args.append("--codespaces")
    
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
    
    # Append any positional arguments for backward compatibility
    if args:
        script_args.extend(args)
    
    return run_script("setup-repos.sh", script_args)


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
    *args
):
    """
    Execute a script inside each cloned repository.
    
    Args:
        file: Path to repos list file (default: repos.list)
        script: Script to run in each repo, relative to repo root (default: run.sh)
        include: Repo name(s) to include (string or list of strings)
        exclude: Repo name(s) to exclude (string or list of strings)
        ensure_setup: If True, run setup-repos.sh before executing scripts
        skip_deps: If True, skip the install-r-deps.sh step
        dry_run: If True, show what would be done without executing
        verbose: If True, enable verbose logging
        continue_on_error: If True, continue on failure and report all results
        *args: Additional arguments passed directly to run-pipeline.sh for backward compatibility
        
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
        
        >>> # Backward compatibility - still works
        >>> run("--script", "build.sh", "--dry-run")
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
    
    # Append any positional arguments for backward compatibility
    if args:
        script_args.extend(args)
    
    return run_script("run-pipeline.sh", script_args)


USAGE = """\
Usage: repos <command> [options]

Commands:
  setup    Clone and configure repositories from a repos.list file
  run      Execute a script inside each cloned repository

Run 'repos <command> --help' for more information on a command.
"""

SUBCOMMAND_SCRIPTS = {
    "setup": "setup-repos.sh",
    "run": "run-pipeline.sh",
}


def main():
    """
    Main entry point for the repos CLI command.
    
    This function is registered as a console script entry point,
    allowing users to run 'repos' from the command line after installation.

    Supports subcommands:
      repos setup [flags]   — delegates to setup-repos.sh
      repos run [flags]     — delegates to run-pipeline.sh
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
