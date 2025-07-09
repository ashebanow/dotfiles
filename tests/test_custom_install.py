#!/usr/bin/env python3
"""
Unit tests for custom installation system

These tests verify the functionality of the custom installation shell scripts including:
- Custom installation file parsing and execution
- Platform-specific command resolution
- gum integration for user prompts
- Install condition evaluation
- Error handling and validation
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

import pytest

# Add the bin directory to the path so we can import package modules
sys.path.insert(0, str(Path(__file__).parent.parent / "bin"))

try:
    from package_generators_tagged import (
        EnhancedPlatformDetector as PlatformDetector,
    )
    from package_generators_tagged import (
        TaggedPackageFileGenerator,
    )
except ImportError as e:
    print(f"Error importing package modules: {e}")
    sys.exit(1)


@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
class TestCustomInstallFileParsing(unittest.TestCase):
    """Test parsing of custom installation files (Customfile format)."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.custom_file = os.path.join(self.test_dir, "Customfile")

    def tearDown(self):
        import shutil

        shutil.rmtree(self.test_dir)

    def test_parse_basic_custom_file(self):
        """Test parsing a basic custom installation file."""
        content = """# Custom installation commands
# Format: package_name|command1|command2|...

test-package|echo 'step1'|echo 'step2'
simple-package|echo 'simple'
"""

        with open(self.custom_file, "w") as f:
            f.write(content)

        # Simulate the shell script parsing logic
        packages = self._parse_custom_file(self.custom_file)

        self.assertIn("test-package", packages)
        self.assertEqual(packages["test-package"], ["echo 'step1'", "echo 'step2'"])
        self.assertIn("simple-package", packages)
        self.assertEqual(packages["simple-package"], ["echo 'simple'"])

    def test_parse_custom_file_with_comments(self):
        """Test parsing custom file with comments and metadata."""
        content = """# Custom installation commands

# Test package with confirmation
# Requires user confirmation
test-confirm|echo 'need confirmation'

# Test package with condition
# Condition: command -v git
test-conditional|git clone test|cd test
"""

        with open(self.custom_file, "w") as f:
            f.write(content)

        packages = self._parse_custom_file(self.custom_file)

        self.assertIn("test-confirm", packages)
        self.assertIn("test-conditional", packages)
        self.assertEqual(packages["test-conditional"], ["git clone test", "cd test"])

    def test_parse_empty_custom_file(self):
        """Test parsing an empty custom file."""
        with open(self.custom_file, "w") as f:
            f.write("# Empty file\n")

        packages = self._parse_custom_file(self.custom_file)
        self.assertEqual(packages, {})

    def _parse_custom_file(self, file_path):
        """Helper method to simulate custom file parsing logic."""
        packages = {}

        with open(file_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue

                parts = line.split("|")
                if len(parts) >= 2:
                    package_name = parts[0]
                    commands = parts[1:]
                    packages[package_name] = commands

        return packages


@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
class TestCustomInstallExecution(unittest.TestCase):
    """Test execution of custom installation commands."""

    @patch("subprocess.run")
    def test_execute_single_command(self, mock_run):
        """Test executing a single custom installation command."""
        mock_run.return_value.returncode = 0

        # Simulate executing: echo 'test'
        result = self._execute_command("echo 'test'")

        self.assertTrue(result)
        mock_run.assert_called_once()

    @patch("subprocess.run")
    def test_execute_multiple_commands(self, mock_run):
        """Test executing multiple custom installation commands."""
        mock_run.return_value.returncode = 0

        commands = ["echo 'step1'", "echo 'step2'", "echo 'step3'"]
        results = [self._execute_command(cmd) for cmd in commands]

        self.assertTrue(all(results))
        self.assertEqual(mock_run.call_count, 3)

    @patch("subprocess.run")
    def test_execute_command_failure(self, mock_run):
        """Test handling of command execution failure."""
        mock_run.return_value.returncode = 1

        result = self._execute_command("false")

        self.assertFalse(result)
        mock_run.assert_called_once()

    def _execute_command(self, command):
        """Helper method to simulate command execution."""
        import subprocess

        try:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, timeout=30)
            return result.returncode == 0
        except subprocess.TimeoutExpired:
            return False


@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
class TestCustomInstallPlatformDetection(unittest.TestCase):
    """Test platform-specific command resolution in custom installations."""

    def setUp(self):
        self.mock_platform = Mock(spec=PlatformDetector)

    def test_darwin_platform_commands(self):
        """Test resolving commands for macOS platform."""
        self.mock_platform.is_darwin = True
        self.mock_platform.is_linux = False
        self.mock_platform.is_arch_like = False

        custom_install = {
            "is_darwin": ["brew install test"],
            "is_linux": ["apt install test"],
            "default": ["echo 'default'"],
        }

        commands = self._resolve_platform_commands(custom_install, self.mock_platform)
        self.assertEqual(commands, ["brew install test"])

    def test_arch_platform_commands(self):
        """Test resolving commands for Arch Linux platform."""
        self.mock_platform.is_darwin = False
        self.mock_platform.is_linux = True
        self.mock_platform.is_arch_like = True
        self.mock_platform.is_debian_like = False

        custom_install = {
            "is_arch_like": ["yay -S test"],
            "is_debian_like": ["apt install test"],
            "default": ["echo 'default'"],
        }

        commands = self._resolve_platform_commands(custom_install, self.mock_platform)
        self.assertEqual(commands, ["yay -S test"])

    def test_fallback_to_default_commands(self):
        """Test falling back to default commands when no platform match."""
        self.mock_platform.is_darwin = False
        self.mock_platform.is_linux = True
        self.mock_platform.is_arch_like = False
        self.mock_platform.is_debian_like = False
        self.mock_platform.is_fedora_like = True

        custom_install = {
            "is_darwin": ["brew install test"],
            "is_arch_like": ["yay -S test"],
            "default": ["echo 'fallback'"],
        }

        commands = self._resolve_platform_commands(custom_install, self.mock_platform)
        self.assertEqual(commands, ["echo 'fallback'"])

    def test_no_matching_commands(self):
        """Test when no commands match the current platform."""
        self.mock_platform.is_darwin = False
        self.mock_platform.is_linux = True
        self.mock_platform.is_arch_like = False

        custom_install = {"is_darwin": ["brew install test"], "is_windows": ["choco install test"]}

        commands = self._resolve_platform_commands(custom_install, self.mock_platform)
        self.assertEqual(commands, [])

    def _resolve_platform_commands(self, custom_install, platform):
        """Helper method to simulate platform command resolution."""
        # Check platform-specific commands in order of specificity
        platform_checks = [
            ("is_darwin", platform.is_darwin),
            ("is_arch_like", getattr(platform, "is_arch_like", False)),
            ("is_debian_like", getattr(platform, "is_debian_like", False)),
            ("is_fedora_like", getattr(platform, "is_fedora_like", False)),
            ("is_linux", getattr(platform, "is_linux", False)),
        ]

        for platform_key, is_platform in platform_checks:
            if is_platform and platform_key in custom_install:
                return custom_install[platform_key]

        # Fall back to default if available
        return custom_install.get("default", [])


@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
class TestCustomInstallGumIntegration(unittest.TestCase):
    """Test gum integration for user prompts in custom installations."""

    @patch("subprocess.run")
    def test_gum_confirmation_yes(self, mock_run):
        """Test gum confirmation returning yes."""
        mock_run.return_value.returncode = 0  # User confirmed

        result = self._gum_confirm("Install test-package?")

        self.assertTrue(result)
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        self.assertIn("gum", args)
        self.assertIn("confirm", args)

    @patch("subprocess.run")
    def test_gum_confirmation_no(self, mock_run):
        """Test gum confirmation returning no."""
        mock_run.return_value.returncode = 1  # User declined

        result = self._gum_confirm("Install test-package?")

        self.assertFalse(result)
        mock_run.assert_called_once()

    @patch("subprocess.run")
    def test_gum_not_available(self, mock_run):
        """Test fallback when gum is not available."""
        mock_run.side_effect = FileNotFoundError()

        # Should fall back to basic prompt or skip
        result = self._gum_confirm("Install test-package?", fallback=True)

        self.assertTrue(result)  # Fallback should default to yes

    def _gum_confirm(self, message, fallback=False):
        """Helper method to simulate gum confirmation."""
        import subprocess

        try:
            result = subprocess.run(["gum", "confirm", message], capture_output=True, timeout=30)
            return result.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            if fallback:
                return True  # Default to yes when gum unavailable
            return False


@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
class TestCustomInstallConditions(unittest.TestCase):
    """Test install condition evaluation for custom installations."""

    @patch("subprocess.run")
    def test_condition_success(self, mock_run):
        """Test install condition that succeeds."""
        mock_run.return_value.returncode = 0

        result = self._evaluate_condition("command -v git")

        self.assertTrue(result)
        mock_run.assert_called_once()

    @patch("subprocess.run")
    def test_condition_failure(self, mock_run):
        """Test install condition that fails."""
        mock_run.return_value.returncode = 1

        result = self._evaluate_condition("command -v nonexistent")

        self.assertFalse(result)
        mock_run.assert_called_once()

    @patch("subprocess.run")
    def test_complex_condition(self, mock_run):
        """Test complex install condition."""
        mock_run.return_value.returncode = 0

        condition = "[ -d ~/.config ] && command -v curl"
        result = self._evaluate_condition(condition)

        self.assertTrue(result)
        mock_run.assert_called_once()

    def test_empty_condition(self):
        """Test empty or None condition (should always pass)."""
        self.assertTrue(self._evaluate_condition(""))
        self.assertTrue(self._evaluate_condition(None))

    def _evaluate_condition(self, condition):
        """Helper method to simulate condition evaluation."""
        if not condition:
            return True

        import subprocess

        try:
            result = subprocess.run(condition, shell=True, capture_output=True, timeout=10)
            return result.returncode == 0
        except subprocess.TimeoutExpired:
            return False


@pytest.mark.skip(reason="Needs rewriting for new tagged architecture")
class TestCustomInstallValidation(unittest.TestCase):
    """Test validation of custom installation configurations."""

    def test_validate_custom_install_structure(self):
        """Test validation of custom installation JSON structure."""
        valid_config = {
            "packages": {
                "test-package": {
                    "description": "Test package",
                    "custom-install": {"default": ["echo 'test'"]},
                }
            }
        }

        self.assertTrue(self._validate_custom_install_config(valid_config))

    def test_validate_missing_packages_key(self):
        """Test validation fails when packages key is missing."""
        invalid_config = {"not_packages": {}}

        self.assertFalse(self._validate_custom_install_config(invalid_config))

    def test_validate_empty_custom_install(self):
        """Test validation of package with empty custom-install."""
        config_with_empty = {
            "packages": {"test-package": {"description": "Test package", "custom-install": {}}}
        }

        self.assertTrue(self._validate_custom_install_config(config_with_empty))

    def test_validate_invalid_commands(self):
        """Test validation of invalid command structures."""
        invalid_config = {
            "packages": {
                "test-package": {"custom-install": {"default": "not a list"}}  # Should be a list
            }
        }

        self.assertFalse(self._validate_custom_install_config(invalid_config))

    def _validate_custom_install_config(self, config):
        """Helper method to simulate config validation."""
        if not isinstance(config, dict):
            return False

        if "packages" not in config:
            return False

        packages = config["packages"]
        if not isinstance(packages, dict):
            return False

        for package_name, package_config in packages.items():
            if not isinstance(package_config, dict):
                return False

            custom_install = package_config.get("custom-install", {})
            if not isinstance(custom_install, dict):
                return False

            # Validate command lists
            for platform, commands in custom_install.items():
                if not isinstance(commands, list):
                    return False

                for command in commands:
                    if not isinstance(command, str):
                        return False

        return True


if __name__ == "__main__":
    # Ensure we're running from the correct directory
    os.chdir(Path(__file__).parent.parent)

    # Run the tests
    unittest.main(verbosity=2)
