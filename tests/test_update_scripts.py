import pytest
from unittest.mock import MagicMock
import repos

@pytest.fixture
def mock_run_script(monkeypatch):
    mock = MagicMock()
    # Mock CompletedProcess
    mock.return_value.returncode = 0
    mock.return_value.stdout = ""
    mock.return_value.stderr = ""
    monkeypatch.setattr(repos, "run_script", mock)
    return mock

def test_update_scripts_no_args(mock_run_script):
    repos.update_scripts()
    mock_run_script.assert_called_once_with("update-scripts.sh", [])

def test_update_scripts_branch(mock_run_script):
    repos.update_scripts(branch="dev")
    mock_run_script.assert_called_once_with("update-scripts.sh", ["--branch", "dev"])

def test_update_scripts_dry_run(mock_run_script):
    repos.update_scripts(dry_run=True)
    mock_run_script.assert_called_once_with("update-scripts.sh", ["--dry-run"])

def test_update_scripts_force(mock_run_script):
    repos.update_scripts(force=True)
    mock_run_script.assert_called_once_with("update-scripts.sh", ["--force"])

def test_update_scripts_combined(mock_run_script):
    repos.update_scripts(branch="feature", dry_run=True, force=True)
    # The order of arguments depends on the implementation in repos/__init__.py
    # From the code: branch then dry_run then force
    mock_run_script.assert_called_once_with("update-scripts.sh", ["--branch", "feature", "--dry-run", "--force"])

def test_update_scripts_raw(mock_run_script):
    repos.update_scripts_raw("--branch", "main", "--force")
    mock_run_script.assert_called_once_with("update-scripts.sh", ["--branch", "main", "--force"])
