# test_build_lambda.py
import pytest
import os
import shutil
import tempfile
from pathlib import Path
from unittest.mock import patch, Mock
from scripts.build_lambda import create_single_layer_package, create_lambda_package

@pytest.fixture
def temp_dir():
    """Create a temporary directory for testing"""
    with tempfile.TemporaryDirectory() as tmpdirname:
        original_dir = os.getcwd()
        os.chdir(tmpdirname)
        # Create a temporary dist directory
        os.makedirs("dist")
        yield tmpdirname
        # Change back to original directory before cleanup
        os.chdir(original_dir)

def test_create_single_layer_package(temp_dir):
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = Mock(returncode=0)
        create_single_layer_package("test-package")
        
        mock_run.assert_called_once()
        assert os.path.exists("dist/lambda_layer_test-package.zip")

def test_create_single_layer_package_custom_version(temp_dir):
    with patch("subprocess.run") as mock_run:
        mock_run.return_value = Mock(returncode=0)
        create_single_layer_package("test-package", python_version="3.9")
        
        call_args = mock_run.call_args[0][0]
        assert "--python-version" in call_args
        assert "3.9" in call_args

def test_create_lambda_package(temp_dir):
    # Create a temporary test file structure
    test_src_dir = Path(temp_dir) / "test_src" / "lambda_functions"
    test_src_dir.mkdir(parents=True)
    test_file = test_src_dir / "test.py"
    test_file.write_text("def test(): pass")
    
    create_lambda_package(str(test_file), "test_lambda")
    assert os.path.exists("dist/test_lambda.zip")

def test_create_lambda_package_existing_no_overwrite(temp_dir):
    # Create test zip in temporary dist directory
    test_zip = Path("dist") / "test_lambda.zip"
    test_zip.write_text("dummy")
    
    with patch("builtins.print") as mock_print:
        create_lambda_package("dummy.py", "test_lambda", overwrite=False)
        mock_print.assert_called_with("dist/test_lambda.zip already exists. Use --overwrite to replace it.")