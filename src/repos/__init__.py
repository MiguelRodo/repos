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
    """
    script_path = get_script_path(script_name)
    
    # Ensure the script is executable
    os.chmod(script_path, 0o755)
    
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


def main():
    """
    Main entry point for the repos CLI command.
    
    This function is registered as a console script entry point,
    allowing users to run 'repos' from the command line after installation.
    """
    # Get arguments from command line (excluding the script name)
    args = sys.argv[1:]
    
    try:
        run_script("setup-repos.sh", args)
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
