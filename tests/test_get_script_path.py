import pytest
from unittest.mock import MagicMock, patch
import repos
from pathlib import Path
import os
import sys

def test_get_script_path_real_file():
    """Verify it finds an actual script like run-pipeline.sh."""
    path = repos.get_script_path("run-pipeline.sh")
    assert os.path.exists(path)
    path_obj = Path(path)
    assert path_obj.name == "run-pipeline.sh"
    assert "repos" in path_obj.parts
    assert "scripts" in path_obj.parts

def test_get_script_path_not_found():
    """Verify it raises FileNotFoundError for a non-existent script."""
    with pytest.raises(FileNotFoundError) as excinfo:
        repos.get_script_path("non-existent-script.sh")
    assert "Cannot find non-existent-script.sh" in str(excinfo.value)

def test_get_script_path_3_9_plus(monkeypatch):
    """Mock sys.version_info to (3, 9) and verify importlib.resources.files is used."""
    monkeypatch.setattr(repos.sys, "version_info", (3, 9, 0))

    mock_files = MagicMock()
    mock_script = MagicMock()
    mock_script.is_file.return_value = True
    # We want str(mock_script) to return our mocked path
    mock_script.__str__.return_value = "/mocked/path/script.sh"
    # Also need to handle how Path(mock_script) or just returning it works
    # get_script_path returns str(script_path)

    mock_files.return_value.joinpath.return_value = mock_script

    # We need to patch 'files' because it's imported inside the function
    with patch("importlib.resources.files", mock_files):
        path = repos.get_script_path("script.sh")
        assert path == "/mocked/path/script.sh"
        mock_files.assert_called_with('repos')

def test_get_script_path_older_python(monkeypatch):
    """Mock sys.version_info to (3, 8) and verify importlib.resources.path is used."""
    monkeypatch.setattr(repos.sys, "version_info", (3, 8, 0))

    mock_path_ctx = MagicMock()
    mock_path = MagicMock()
    mock_path.is_file.return_value = True
    mock_path.__str__.return_value = "/mocked/path/script.sh"
    mock_path_ctx.__enter__.return_value = mock_path

    # patch the importlib.resources.path which is used in the else block
    with patch("importlib.resources.path", return_value=mock_path_ctx) as mock_path_func:
        path = repos.get_script_path("script.sh")
        assert path == "/mocked/path/script.sh"
        mock_path_func.assert_called_with('repos.scripts', 'script.sh')

def test_get_script_path_fallback(monkeypatch):
    """Verify it falls back to __file__ relative path when importlib fails."""
    # Force an error in the try block
    monkeypatch.setattr(repos.sys, "version_info", (3, 9, 0))

    with patch("importlib.resources.files", side_effect=ImportError):
        # Should fall back to __file__ relative path
        module_dir = Path(repos.__file__).parent
        expected_path = str(module_dir / 'scripts' / 'run-pipeline.sh')

        path = repos.get_script_path("run-pipeline.sh")
        assert path == expected_path

def test_get_script_path_is_file_false(monkeypatch):
    """Verify it falls back if is_file() is False in importlib path."""
    monkeypatch.setattr(repos.sys, "version_info", (3, 9, 0))

    mock_files = MagicMock()
    mock_script = MagicMock()
    mock_script.is_file.return_value = False
    mock_files.return_value.joinpath.return_value = mock_script

    with patch("importlib.resources.files", mock_files):
        # It should pass through the try block (since it doesn't return)
        # and then use the fallback __file__ path
        module_dir = Path(repos.__file__).parent
        expected_path = str(module_dir / 'scripts' / 'run-pipeline.sh')

        path = repos.get_script_path("run-pipeline.sh")
        assert path == expected_path
