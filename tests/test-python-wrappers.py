#!/usr/bin/env python3
"""Test Python wrapper functions with idiomatic syntax"""

import sys
import os
from pathlib import Path

# Add src to path to import repos module
repo_root = Path(__file__).parent.parent
sys.path.insert(0, str(repo_root / "src"))

# Import the module
import repos

# Mock run_script to capture arguments
test_args = {}

def mock_run_script(script_name, args=None):
    global test_args
    test_args = {"script": script_name, "args": args or []}
    # Return a mock CompletedProcess
    class MockResult:
        returncode = 0
    return MockResult()

# Replace the real function with our mock
repos.run_script = mock_run_script

# Test tracking
test_count = 0
pass_count = 0
fail_count = 0

def test(description, func):
    global test_count, pass_count, fail_count
    test_count += 1
    print(f"Test {test_count}: {description}... ", end="")
    
    try:
        func()
        print("PASSED")
        pass_count += 1
    except AssertionError as e:
        print(f"FAILED\n  Error: {e}")
        fail_count += 1
    except Exception as e:
        print(f"FAILED\n  Unexpected error: {e}")
        fail_count += 1

# Test repos.setup with idiomatic syntax
def test_setup_no_args():
    repos.setup()
    assert test_args["script"] == "setup-repos.sh"
    assert test_args["args"] == []

def test_setup_public():
    repos.setup(public=True)
    assert test_args["script"] == "setup-repos.sh"
    assert "--public" in test_args["args"]

def test_setup_file():
    repos.setup(file="custom.list")
    assert test_args["script"] == "setup-repos.sh"
    assert "-f" in test_args["args"]
    assert "custom.list" in test_args["args"]

def test_setup_multiple_options():
    repos.setup(public=True, codespaces=True)
    assert test_args["script"] == "setup-repos.sh"
    assert "--public" in test_args["args"]
    assert "--codespaces" in test_args["args"]

def test_setup_devcontainer_list():
    repos.setup(devcontainer=["path1", "path2"])
    assert test_args["script"] == "setup-repos.sh"
    dc_indices = [i for i, x in enumerate(test_args["args"]) if x == "-d"]
    assert len(dc_indices) == 2
    assert test_args["args"][dc_indices[0] + 1] == "path1"
    assert test_args["args"][dc_indices[1] + 1] == "path2"

def test_setup_devcontainer_single():
    repos.setup(devcontainer="path1")
    assert test_args["script"] == "setup-repos.sh"
    assert "-d" in test_args["args"]
    assert "path1" in test_args["args"]

def test_setup_debug():
    repos.setup(debug=True)
    assert test_args["script"] == "setup-repos.sh"
    assert "--debug" in test_args["args"]

def test_setup_debug_file_bool():
    repos.setup(debug_file=True)
    assert test_args["script"] == "setup-repos.sh"
    assert "--debug-file" in test_args["args"]

def test_setup_debug_file_path():
    repos.setup(debug_file="debug.log")
    assert test_args["script"] == "setup-repos.sh"
    assert "--debug-file" in test_args["args"]
    assert "debug.log" in test_args["args"]

def test_setup_permissions():
    repos.setup(permissions="all")
    assert test_args["script"] == "setup-repos.sh"
    assert "--permissions" in test_args["args"]
    assert "all" in test_args["args"]

def test_setup_tool():
    repos.setup(tool="jq")
    assert test_args["script"] == "setup-repos.sh"
    assert "-t" in test_args["args"]
    assert "jq" in test_args["args"]

# Test backward compatibility
def test_setup_backward_compat():
    repos.setup_raw("--public", "--codespaces")
    assert test_args["script"] == "setup-repos.sh"
    assert "--public" in test_args["args"]
    assert "--codespaces" in test_args["args"]

# Test repos.run with idiomatic syntax
def test_run_no_args():
    repos.run()
    assert test_args["script"] == "run-pipeline.sh"
    assert test_args["args"] == []

def test_run_script():
    repos.run(script="build.sh")
    assert test_args["script"] == "run-pipeline.sh"
    assert "--script" in test_args["args"]
    assert "build.sh" in test_args["args"]

def test_run_flags():
    repos.run(dry_run=True, verbose=True)
    assert test_args["script"] == "run-pipeline.sh"
    assert "-n" in test_args["args"]
    assert "-v" in test_args["args"]

def test_run_include_list():
    repos.run(include=["repo1", "repo2"])
    assert test_args["script"] == "run-pipeline.sh"
    i_idx = test_args["args"].index("-i")
    assert test_args["args"][i_idx + 1] == "repo1,repo2"

def test_run_include_string():
    repos.run(include="repo1,repo2")
    assert test_args["script"] == "run-pipeline.sh"
    i_idx = test_args["args"].index("-i")
    assert test_args["args"][i_idx + 1] == "repo1,repo2"

def test_run_exclude_string():
    repos.run(exclude="repo3")
    assert test_args["script"] == "run-pipeline.sh"
    e_idx = test_args["args"].index("-e")
    assert test_args["args"][e_idx + 1] == "repo3"

def test_run_ensure_setup_skip_deps():
    repos.run(ensure_setup=True, skip_deps=True)
    assert test_args["script"] == "run-pipeline.sh"
    assert "--ensure-setup" in test_args["args"]
    assert "-d" in test_args["args"]

def test_run_continue_on_error():
    repos.run(continue_on_error=True)
    assert test_args["script"] == "run-pipeline.sh"
    assert "--continue-on-error" in test_args["args"]

def test_run_file():
    repos.run(file="custom.list")
    assert test_args["script"] == "run-pipeline.sh"
    assert "-f" in test_args["args"]
    assert "custom.list" in test_args["args"]

# Test backward compatibility
def test_run_backward_compat():
    repos.run_raw("--script", "test.sh", "--dry-run")
    assert test_args["script"] == "run-pipeline.sh"
    assert "--script" in test_args["args"]
    assert "test.sh" in test_args["args"]
    assert "--dry-run" in test_args["args"]

# Run all tests
if __name__ == "__main__":
    print("Testing Python wrapper functions\n")
    
    test("repos.setup() with no args", test_setup_no_args)
    test("repos.setup(public=True)", test_setup_public)
    test("repos.setup(file='custom.list')", test_setup_file)
    test("repos.setup(public=True, codespaces=True)", test_setup_multiple_options)
    test("repos.setup(devcontainer=['path1', 'path2'])", test_setup_devcontainer_list)
    test("repos.setup(devcontainer='path1')", test_setup_devcontainer_single)
    test("repos.setup(debug=True)", test_setup_debug)
    test("repos.setup(debug_file=True)", test_setup_debug_file_bool)
    test("repos.setup(debug_file='debug.log')", test_setup_debug_file_path)
    test("repos.setup(permissions='all')", test_setup_permissions)
    test("repos.setup(tool='jq')", test_setup_tool)
    test("repos.setup_raw('--public', '--codespaces') backward compatibility", test_setup_backward_compat)
    
    test("repos.run() with no args", test_run_no_args)
    test("repos.run(script='build.sh')", test_run_script)
    test("repos.run(dry_run=True, verbose=True)", test_run_flags)
    test("repos.run(include=['repo1', 'repo2'])", test_run_include_list)
    test("repos.run(include='repo1,repo2')", test_run_include_string)
    test("repos.run(exclude='repo3')", test_run_exclude_string)
    test("repos.run(ensure_setup=True, skip_deps=True)", test_run_ensure_setup_skip_deps)
    test("repos.run(continue_on_error=True)", test_run_continue_on_error)
    test("repos.run(file='custom.list')", test_run_file)
    test("repos.run_raw('--script', 'test.sh', '--dry-run') backward compatibility", test_run_backward_compat)
    
    print("\n" + "=" * 40)
    print(f"Total tests: {test_count}")
    print(f"Passed: {pass_count}")
    print(f"Failed: {fail_count}")
    print("=" * 40)
    
    sys.exit(0 if fail_count == 0 else 1)
