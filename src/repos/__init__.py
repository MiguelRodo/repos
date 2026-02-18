"""
repos - Multi-Repository Management Tool

A Python wrapper for the repos Bash scripts that manage multiple related Git repositories.
"""

import os
import sys
import subprocess
from pathlib import Path

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
