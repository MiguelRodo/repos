#!/usr/bin/env python3
"""Test Python wrapper functions with idiomatic syntax"""

import sys
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

# Test repos.workspace with idiomatic syntax
def test_workspace_no_args():
    repos.workspace()
    assert test_args["script"] == "helper/vscode-workspace-add.sh"
    assert test_args["args"] == []

def test_workspace_file():
    repos.workspace(file="custom.list")
    assert test_args["script"] == "helper/vscode-workspace-add.sh"
    assert "-f" in test_args["args"]
    assert "custom.list" in test_args["args"]

def test_workspace_debug():
    repos.workspace(debug=True)
    assert test_args["script"] == "helper/vscode-workspace-add.sh"
    assert "--debug" in test_args["args"]

def test_workspace_debug_file_bool():
    repos.workspace(debug_file=True)
    assert test_args["script"] == "helper/vscode-workspace-add.sh"
    assert "--debug-file" in test_args["args"]

def test_workspace_debug_file_path():
    repos.workspace(debug_file="debug.log")
    assert test_args["script"] == "helper/vscode-workspace-add.sh"
    assert "--debug-file" in test_args["args"]
    assert "debug.log" in test_args["args"]

# Test repos.codespace with idiomatic syntax
def test_codespace_no_args():
    repos.codespace()
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    assert test_args["args"] == []

def test_codespace_file():
    repos.codespace(file="custom.list")
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    assert "-f" in test_args["args"]
    assert "custom.list" in test_args["args"]

def test_codespace_devcontainer_list():
    repos.codespace(devcontainer=["path1", "path2"])
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    dc_indices = [i for i, x in enumerate(test_args["args"]) if x == "-d"]
    assert len(dc_indices) == 2
    assert test_args["args"][dc_indices[0] + 1] == "path1"
    assert test_args["args"][dc_indices[1] + 1] == "path2"

def test_codespace_devcontainer_single():
    repos.codespace(devcontainer="path1")
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    assert "-d" in test_args["args"]
    assert "path1" in test_args["args"]

def test_codespace_permissions():
    repos.codespace(permissions="all")
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    assert "--permissions" in test_args["args"]
    assert "all" in test_args["args"]

def test_codespace_tool():
    repos.codespace(tool="jq")
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    assert "-t" in test_args["args"]
    assert "jq" in test_args["args"]

def test_codespace_debug():
    repos.codespace(debug=True)
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    assert "--debug" in test_args["args"]

# Test raw helpers
def test_workspace_raw():
    repos.workspace_raw("-f", "custom.list")
    assert test_args["script"] == "helper/vscode-workspace-add.sh"
    assert "-f" in test_args["args"]
    assert "custom.list" in test_args["args"]

def test_codespace_raw():
    repos.codespace_raw("-d", ".devcontainer/devcontainer.json")
    assert test_args["script"] == "helper/codespaces-auth-add.sh"
    assert "-d" in test_args["args"]
    assert ".devcontainer/devcontainer.json" in test_args["args"]

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
    
    test("repos.workspace() with no args", test_workspace_no_args)
    test("repos.workspace(file='custom.list')", test_workspace_file)
    test("repos.workspace(debug=True)", test_workspace_debug)
    test("repos.workspace(debug_file=True)", test_workspace_debug_file_bool)
    test("repos.workspace(debug_file='debug.log')", test_workspace_debug_file_path)
    test("repos.codespace() with no args", test_codespace_no_args)
    test("repos.codespace(file='custom.list')", test_codespace_file)
    test("repos.codespace(devcontainer=['path1', 'path2'])", test_codespace_devcontainer_list)
    test("repos.codespace(devcontainer='path1')", test_codespace_devcontainer_single)
    test("repos.codespace(permissions='all')", test_codespace_permissions)
    test("repos.codespace(tool='jq')", test_codespace_tool)
    test("repos.codespace(debug=True)", test_codespace_debug)
    test("repos.workspace_raw('-f', 'custom.list')", test_workspace_raw)
    test("repos.codespace_raw('-d', '.devcontainer/devcontainer.json')", test_codespace_raw)
    
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
