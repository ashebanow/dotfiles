#!/usr/bin/env python3
"""
Unit tests for package_analysis.py

These tests verify the functionality of package analysis including:
- Custom installation loading and merging
- Package entry generation
- TOML writing with hierarchical data
- Platform-specific package resolution
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

# Add the bin directory to the path so we can import package_analysis
sys.path.insert(0, str(Path(__file__).parent.parent / "bin"))

try:
    import package_analysis
    from package_analysis import (
        RepologyClient,
        generate_package_entry,
        is_valid_package_name,
        load_custom_installations,
        load_toml,
        merge_custom_installation,
        write_toml,
    )
except ImportError as e:
    print(f"Error importing package_analysis: {e}")
    sys.exit(1)


class TestLoadCustomInstallations(unittest.TestCase):
    """Test loading custom installation configurations."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.custom_install_file = os.path.join(self.test_dir, "custom_install.json")

    def tearDown(self):
        import shutil

        shutil.rmtree(self.test_dir)

    def test_load_valid_custom_install_file(self):
        """Test loading a valid custom installation file."""
        test_data = {
            "packages": {
                "test-package": {
                    "description": "Test package",
                    "custom-install": {"default": ["echo 'test'"]},
                }
            }
        }

        with open(self.custom_install_file, "w") as f:
            json.dump(test_data, f)

        result = load_custom_installations(self.custom_install_file)

        self.assertEqual(result, test_data["packages"])
        self.assertIn("test-package", result)
        self.assertEqual(result["test-package"]["description"], "Test package")

    def test_load_nonexistent_file(self):
        """Test loading a non-existent file returns empty dict."""
        result = load_custom_installations("/nonexistent/file.json")
        self.assertEqual(result, {})

    def test_load_invalid_json(self):
        """Test loading invalid JSON returns empty dict."""
        with open(self.custom_install_file, "w") as f:
            f.write("invalid json content")

        result = load_custom_installations(self.custom_install_file)
        self.assertEqual(result, {})

    def test_load_missing_packages_key(self):
        """Test loading JSON without packages key returns empty dict."""
        test_data = {"not_packages": {}}

        with open(self.custom_install_file, "w") as f:
            json.dump(test_data, f)

        result = load_custom_installations(self.custom_install_file)
        self.assertEqual(result, {})


class TestMergeCustomInstallation(unittest.TestCase):
    """Test merging custom installation data into package entries."""

    def test_merge_basic_custom_install(self):
        """Test merging basic custom installation data."""
        entry = {"arch-pkg": "test-pkg", "description": "Original description"}

        custom_installs = {
            "test-package": {
                "custom-install": {"default": ["echo 'test'"]},
                "description": "Custom description",
            }
        }

        result = merge_custom_installation(entry, "test-package", custom_installs)

        self.assertEqual(result["custom-install"], {"default": ["echo 'test'"]})
        self.assertEqual(result["description"], "Custom description")

    def test_merge_priority_settings(self):
        """Test merging custom installation priority."""
        entry = {}

        # Test non-default priority is included
        custom_installs = {
            "test-package": {
                "custom-install": {"default": ["echo 'test'"]},
                "custom-install-priority": "fallback",
            }
        }

        result = merge_custom_installation(entry, "test-package", custom_installs)
        self.assertEqual(result["custom-install-priority"], "fallback")

        # Test default priority is not included
        custom_installs["test-package"]["custom-install-priority"] = "always"
        result = merge_custom_installation(entry, "test-package", custom_installs)
        self.assertNotIn("custom-install-priority", result)

    def test_merge_additional_fields(self):
        """Test merging additional custom fields."""
        entry = {}

        custom_installs = {
            "test-package": {
                "custom-install": {"default": ["echo 'test'"]},
                "requires-confirmation": True,
                "install-condition": "command -v test",
            }
        }

        result = merge_custom_installation(entry, "test-package", custom_installs)

        self.assertTrue(result["requires-confirmation"])
        self.assertEqual(result["install-condition"], "command -v test")

    def test_merge_package_not_in_custom(self):
        """Test merging when package is not in custom installations."""
        entry = {"arch-pkg": "test-pkg"}
        custom_installs = {}

        result = merge_custom_installation(entry, "test-package", custom_installs)

        self.assertEqual(result, entry)  # Should be unchanged


class TestWriteToml(unittest.TestCase):
    """Test TOML writing functionality."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.toml_file = os.path.join(self.test_dir, "test.toml")

    def tearDown(self):
        import shutil

        shutil.rmtree(self.test_dir)

    def test_write_basic_toml(self):
        """Test writing basic TOML structure."""
        data = {
            "test-package": {
                "arch-pkg": "test-pkg",
                "description": "Test package",
                "prefer_flatpak": False,
            }
        }

        write_toml(data, self.toml_file)

        with open(self.toml_file) as f:
            content = f.read()

        self.assertIn("[test-package]", content)
        self.assertIn('arch-pkg = "test-pkg"', content)
        self.assertIn('description = "Test package"', content)
        self.assertIn("prefer_flatpak = false", content)

    def test_write_hierarchical_custom_install(self):
        """Test writing hierarchical custom installation data."""
        data = {
            "test-package": {
                "description": "Test package",
                "custom-install": {
                    "is_darwin": ["brew install test"],
                    "default": ["echo 'install test'"],
                },
            }
        }

        write_toml(data, self.toml_file)

        with open(self.toml_file) as f:
            content = f.read()

        self.assertIn("[test-package.custom-install]", content)
        self.assertIn("is_darwin = [", content)
        self.assertIn('"brew install test",', content)
        self.assertIn("default = [", content)

    def test_write_quoted_section_names(self):
        """Test writing section names that need quoting."""
        data = {
            "test@1.0": {"description": "Versioned package"},
            "test.app": {"description": "Dotted package"},
            "org.test.App": {"description": "Flatpak ID"},
        }

        write_toml(data, self.toml_file)

        with open(self.toml_file) as f:
            content = f.read()

        self.assertIn('["test@1.0"]', content)
        self.assertIn('["test.app"]', content)
        self.assertIn('["org.test.App"]', content)


class TestValidPackageName(unittest.TestCase):
    """Test package name validation."""

    def test_valid_package_names(self):
        """Test various valid package names."""
        valid_names = [
            "test-package",
            "test_package",
            "testpackage",
            "test123",
            "org.test.App",
            "test@1.0",
        ]

        for name in valid_names:
            with self.subTest(name=name):
                self.assertTrue(is_valid_package_name(name))

    def test_invalid_package_names(self):
        """Test invalid package names."""
        invalid_names = [
            "",
            "   ",
            "app",  # Single TLD component
            "com",  # Single TLD component
            "org",  # Single TLD component
        ]

        for name in invalid_names:
            with self.subTest(name=name):
                self.assertFalse(is_valid_package_name(name))


class TestGeneratePackageEntry(unittest.TestCase):
    """Test package entry generation."""

    def setUp(self):
        # Mock RepologyClient to avoid actual network calls
        self.mock_client = Mock(spec=RepologyClient)
        self.mock_client._is_flatpak_application_id.return_value = False
        self.mock_client.query_package.return_value = None
        self.mock_client.package_aliases = {}

    def test_generate_basic_entry(self):
        """Test generating a basic package entry."""
        existing_toml = {}

        key_name, entry = generate_package_entry("test-package", self.mock_client, existing_toml)

        self.assertEqual(key_name, "test-package")
        self.assertIn("arch-pkg", entry)
        self.assertIn("apt-pkg", entry)
        self.assertIn("description", entry)
        self.assertIn("custom-install", entry)

    def test_generate_flatpak_entry(self):
        """Test generating entry for Flatpak application ID."""
        self.mock_client._is_flatpak_application_id.return_value = True
        self.mock_client._extract_project_name_from_flatpak_id.return_value = "testapp"

        existing_toml = {}

        key_name, entry = generate_package_entry(
            "org.test.TestApp", self.mock_client, existing_toml
        )

        self.assertEqual(key_name, "testapp")
        self.assertEqual(entry["flatpak-pkg"], "org.test.TestApp")
        self.assertTrue(entry["prefer_flatpak"])

    def test_generate_tapped_package_entry(self):
        """Test generating entry for Homebrew tapped package."""
        existing_toml = {}

        key_name, entry = generate_package_entry(
            "custom-tap/test-package", self.mock_client, existing_toml
        )

        self.assertEqual(key_name, "test-package")
        self.assertEqual(entry["brew-tap"], "custom-tap")


class TestRepologyClientMocking(unittest.TestCase):
    """Test RepologyClient with mocked responses."""

    @patch("package_analysis.requests")
    def test_repology_client_successful_query(self, mock_requests):
        """Test successful Repology API query."""
        # Mock successful response
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = [
            {
                "repo": "arch",
                "srcname": "test-package",
                "binname": "test-package",
                "version": "1.0.0",
                "summary": "Test package",
            }
        ]
        mock_requests.get.return_value = mock_response

        client = RepologyClient(cache_file=None)
        result = client.query_package("test-package")

        self.assertIsNotNone(result)
        self.assertIn("platforms", result)
        self.assertIn("package_names", result)

    @patch("package_analysis.requests")
    def test_repology_client_not_found(self, mock_requests):
        """Test Repology API returning 404."""
        mock_response = Mock()
        mock_response.status_code = 404
        mock_requests.get.return_value = mock_response

        client = RepologyClient(cache_file=None)
        result = client.query_package("nonexistent-package")

        self.assertIsNone(result)


if __name__ == "__main__":
    # Ensure we're running from the correct directory
    os.chdir(Path(__file__).parent.parent)

    # Run the tests
    unittest.main(verbosity=2)
