#!/usr/bin/env python3
"""
Integration tests for the complete package management workflow

These tests verify the end-to-end functionality including:
- Package mapping generation from Repology cache
- Custom installation merging
- Package file generation (Brewfile, Archfile, etc.)
- Cross-platform package resolution
- Integration between analysis and generation components
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock
import pytest

# Add the bin directory to the path so we can import package modules
sys.path.insert(0, str(Path(__file__).parent.parent / "bin"))

try:
    import package_analysis
    import package_generators
    from package_analysis import (
        RepologyClient,
        load_custom_installations,
        merge_custom_installation,
    )
    from package_generators import PackageFileGenerator, PackageFilter, PlatformDetector
except ImportError as e:
    print(f"Error importing package modules: {e}")
    sys.exit(1)


@pytest.mark.integration
class TestPackageWorkflowIntegration(unittest.TestCase):
    """Test complete package management workflow integration."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.cache_file = os.path.join(self.test_dir, "cache.json")
        self.toml_file = os.path.join(self.test_dir, "package_mappings.toml")
        self.custom_install_file = os.path.join(self.test_dir, "custom_install.json")

        # Create test cache data
        self.test_cache = {
            "vim": [
                {
                    "repo": "arch",
                    "srcname": "vim",
                    "binname": "vim",
                    "version": "9.0",
                    "summary": "Vi Improved text editor",
                },
                {
                    "repo": "ubuntu_22_04",
                    "srcname": "vim",
                    "binname": "vim",
                    "version": "8.2",
                    "summary": "Vi Improved text editor",
                },
                {
                    "repo": "homebrew",
                    "srcname": "vim",
                    "binname": "vim",
                    "version": "9.0",
                    "summary": "Vi Improved text editor",
                },
            ],
            "tailscale": [
                {
                    "repo": "homebrew_casks",
                    "srcname": "tailscale",
                    "binname": "tailscale",
                    "version": "1.50.0",
                    "summary": "VPN client",
                }
            ],
        }

        # Create test custom installations
        self.test_custom_install = {
            "packages": {
                "tailscale": {
                    "description": "Tailscale VPN client",
                    "custom-install": {
                        "is_darwin": ["brew install --cask tailscale"],
                        "is_debian_like": ["curl -fsSL https://tailscale.com/install.sh | sh"],
                        "default": ["echo 'Please install manually'"],
                    },
                    "custom-install-priority": "always",
                },
                "custom-only-package": {
                    "description": "Package only available via custom install",
                    "custom-install": {"default": ["echo 'Installing custom package'"]},
                    "custom-install-priority": "fallback",
                },
            }
        }

        # Write test files
        with open(self.cache_file, "w") as f:
            json.dump(self.test_cache, f)

        with open(self.custom_install_file, "w") as f:
            json.dump(self.test_custom_install, f)

    def tearDown(self):
        import shutil

        shutil.rmtree(self.test_dir)

    def test_complete_package_analysis_workflow(self):
        """Test the complete package analysis and TOML generation workflow."""
        # Test basic TOML loading and custom installation merging
        custom_installs = load_custom_installations(self.custom_install_file)

        # Verify custom installations loaded correctly
        self.assertIn("tailscale", custom_installs)
        self.assertIn("custom-only-package", custom_installs)

        # Test merging custom installation into a basic entry
        basic_entry = {"arch-pkg": "tailscale", "apt-pkg": "tailscale", "description": "VPN client"}

        merged_entry = merge_custom_installation(basic_entry, "tailscale", custom_installs)

        # Verify the merge worked correctly
        self.assertIn("custom-install", merged_entry)
        self.assertIn("is_darwin", merged_entry["custom-install"])
        self.assertEqual(
            merged_entry["custom-install"]["is_darwin"], ["brew install --cask tailscale"]
        )

        # Write and read back TOML
        test_toml = {"tailscale": merged_entry}
        package_analysis.write_toml(test_toml, self.toml_file)

        # Verify the file was written correctly
        self.assertTrue(os.path.exists(self.toml_file))

        # Load and verify TOML content
        loaded_toml = package_analysis.load_toml(self.toml_file)

        self.assertIn("tailscale", loaded_toml)
        tailscale_entry = loaded_toml["tailscale"]
        self.assertIn("custom-install", tailscale_entry)
        self.assertIn("is_darwin", tailscale_entry["custom-install"])

    def test_complete_package_generation_workflow(self):
        """Test the complete package file generation workflow."""
        # Use the existing test TOML data
        toml_data = package_analysis.load_toml(
            Path(__file__).parent / "assets/package_mapping/test_complete_mappings.toml"
        )

        # Test on different mock platforms
        platforms_to_test = [
            {
                "is_darwin": True,
                "is_linux": False,
                "is_arch_like": False,
                "is_debian_like": False,
                "is_fedora_like": False,
                "supports_homebrew": lambda: True,
                "supports_flatpak": lambda: False,
                "get_native_package_manager": lambda: "homebrew",
            },
            {
                "is_darwin": False,
                "is_linux": True,
                "is_arch_like": True,
                "is_debian_like": False,
                "is_fedora_like": False,
                "supports_homebrew": lambda: False,
                "supports_flatpak": lambda: True,
                "get_native_package_manager": lambda: "arch",
            },
            {
                "is_darwin": False,
                "is_linux": True,
                "is_arch_like": False,
                "is_debian_like": True,
                "is_fedora_like": False,
                "supports_homebrew": lambda: False,
                "supports_flatpak": lambda: True,
                "get_native_package_manager": lambda: "apt",
            },
        ]

        for platform_config in platforms_to_test:
            with self.subTest(
                platform=platform_config.get("get_native_package_manager", lambda: "unknown")()
            ):
                # Create mock platform
                mock_platform = Mock(spec=PlatformDetector)
                for attr, value in platform_config.items():
                    setattr(mock_platform, attr, value)

                # Create filter and generator
                package_filter = PackageFilter(toml_data, mock_platform)
                file_generator = PackageFileGenerator()

                # Test native package generation
                native_packages = package_filter.get_filtered_packages("native")
                if native_packages:
                    if mock_platform.is_darwin:
                        brewfile = file_generator.generate_brewfile(native_packages, toml_data)
                        self.assertIsInstance(brewfile, str)
                        self.assertIn("# Platform-specific packages", brewfile)
                    elif mock_platform.is_arch_like:
                        archfile = file_generator.generate_archfile(native_packages, toml_data)
                        self.assertIsInstance(archfile, str)
                        # Should contain some packages from our test data
                        self.assertIn("test-package", archfile)
                    elif mock_platform.is_debian_like:
                        aptfile = file_generator.generate_simple_list(native_packages)
                        self.assertIsInstance(aptfile, str)
                        # Should contain some packages from our test data
                        self.assertIn("test-package", aptfile)

                # Test custom package generation
                custom_packages = package_filter.get_filtered_packages("custom")
                if custom_packages:
                    customfile = file_generator.generate_customfile(custom_packages, toml_data)

                    # Should contain test-custom-always (always priority)
                    self.assertIn("test-custom-always", customfile)

                    # Should contain test-custom-fallback (fallback priority, no other options)
                    self.assertIn("test-custom-fallback", customfile)

                # Test Flatpak generation if supported
                if mock_platform.supports_flatpak():
                    flatpak_packages = package_filter.get_filtered_packages("flatpak")
                    if flatpak_packages:
                        flatpakfile = file_generator.generate_simple_list(flatpak_packages)
                        # Our test data has Flatpak packages
                        self.assertIsInstance(flatpakfile, str)
                        self.assertIn("org.test.TestApp", flatpakfile)

    def test_cross_platform_package_resolution(self):
        """Test that packages are resolved correctly across different platforms."""
        # Load test TOML data
        toml_data = package_analysis.load_toml(
            Path(__file__).parent / "assets/package_mapping/test_complete_mappings.toml"
        )

        # Test platform-specific behaviors
        test_scenarios = [
            {
                "name": "macOS",
                "platform": {
                    "is_darwin": True,
                    "is_linux": False,
                    "is_arch_like": False,
                    "is_debian_like": False,
                    "is_fedora_like": False,
                    "supports_homebrew": lambda: True,
                    "supports_flatpak": lambda: False,
                    "get_native_package_manager": lambda: "homebrew",
                },
                "expected_homebrew": ["test-standard-package", "test-tapped-package"],
                "expected_homebrew_darwin": ["test-homebrew-cask"],
                "expected_custom": ["test-custom-always"],
            },
            {
                "name": "Arch Linux",
                "platform": {
                    "is_darwin": False,
                    "is_linux": True,
                    "is_arch_like": True,
                    "is_debian_like": False,
                    "is_fedora_like": False,
                    "supports_homebrew": lambda: False,
                    "supports_flatpak": lambda: True,
                    "get_native_package_manager": lambda: "arch",
                },
                "expected_native": ["test-standard-package", "test-aur-package"],
                "expected_flatpak": ["test-flatpak-package"],
                "expected_custom": ["test-custom-always", "test-custom-fallback"],
            },
            {
                "name": "Ubuntu",
                "platform": {
                    "is_darwin": False,
                    "is_linux": True,
                    "is_arch_like": False,
                    "is_debian_like": True,
                    "is_fedora_like": False,
                    "supports_homebrew": lambda: False,
                    "supports_flatpak": lambda: True,
                    "get_native_package_manager": lambda: "apt",
                },
                "expected_native": ["test-standard-package"],
                "expected_flatpak": ["test-flatpak-package"],
                "expected_custom": ["test-custom-always", "test-custom-fallback"],
            },
        ]

        for scenario in test_scenarios:
            with self.subTest(platform=scenario["name"]):
                # Create mock platform
                mock_platform = Mock(spec=PlatformDetector)
                for attr, value in scenario["platform"].items():
                    setattr(mock_platform, attr, value)

                # Create filter
                package_filter = PackageFilter(toml_data, mock_platform)

                # Test native packages
                if "expected_native" in scenario:
                    native_packages = package_filter.get_filtered_packages("native")
                    expected_native = scenario["expected_native"]
                    for pkg in expected_native:
                        self.assertIn(
                            pkg,
                            native_packages,
                            f"Expected {pkg} in native packages for {scenario['name']}",
                        )

                # Test Homebrew packages (for macOS)
                if "expected_homebrew" in scenario:
                    homebrew_packages = package_filter.get_filtered_packages("homebrew")
                    for pkg in scenario["expected_homebrew"]:
                        self.assertIn(
                            pkg,
                            homebrew_packages,
                            f"Expected {pkg} in Homebrew packages for {scenario['name']}",
                        )

                # Test Homebrew Darwin packages (casks)
                if "expected_homebrew_darwin" in scenario:
                    homebrew_darwin_packages = package_filter.get_filtered_packages(
                        "homebrew-darwin"
                    )
                    for pkg in scenario["expected_homebrew_darwin"]:
                        self.assertIn(
                            pkg,
                            homebrew_darwin_packages,
                            f"Expected {pkg} in Homebrew Darwin packages for {scenario['name']}",
                        )

                # Test Flatpak packages
                if "expected_flatpak" in scenario:
                    flatpak_packages = package_filter.get_filtered_packages("flatpak")
                    for pkg in scenario["expected_flatpak"]:
                        self.assertIn(
                            pkg,
                            flatpak_packages,
                            f"Expected {pkg} in Flatpak packages for {scenario['name']}",
                        )

                # Test custom packages
                if "expected_custom" in scenario:
                    custom_packages = package_filter.get_filtered_packages("custom")
                    for pkg in scenario["expected_custom"]:
                        self.assertIn(
                            pkg,
                            custom_packages,
                            f"Expected {pkg} in custom packages for {scenario['name']}",
                        )

    def test_package_priority_resolution(self):
        """Test that custom installation priorities are respected."""
        # Load test TOML data
        toml_data = package_analysis.load_toml(
            Path(__file__).parent / "assets/package_mapping/test_complete_mappings.toml"
        )

        # Create a mock platform where standard packages are available
        mock_platform = Mock(spec=PlatformDetector)
        mock_platform.is_darwin = False
        mock_platform.is_linux = True
        mock_platform.is_arch_like = True
        mock_platform.is_debian_like = False
        mock_platform.is_fedora_like = False
        mock_platform.supports_homebrew.return_value = False
        mock_platform.supports_flatpak.return_value = True
        mock_platform.get_native_package_manager.return_value = "arch"

        package_filter = PackageFilter(toml_data, mock_platform)

        # Test "always" priority - should override native packages
        custom_packages = package_filter.get_filtered_packages("custom")
        native_packages = package_filter.get_filtered_packages("native")

        # test-custom-always should appear in custom, not native (priority = always)
        self.assertIn("test-custom-always", custom_packages)
        self.assertNotIn("test-custom-always", native_packages)

        # test-custom-fallback should appear in custom because no native option available
        self.assertIn("test-custom-fallback", custom_packages)

        # test-standard-package should appear in native, not custom
        self.assertIn("test-standard-package", native_packages)
        self.assertNotIn("test-standard-package", custom_packages)


class TestPackageWorkflowErrorHandling(unittest.TestCase):
    """Test error handling in package workflow integration."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()

    def tearDown(self):
        import shutil

        shutil.rmtree(self.test_dir)

    def test_missing_cache_file_handling(self):
        """Test handling of missing cache file."""
        nonexistent_cache = os.path.join(self.test_dir, "nonexistent.json")

        # Test RepologyClient with nonexistent cache file
        client = package_analysis.RepologyClient(cache_file=nonexistent_cache)

        # Should handle missing file gracefully and return empty dict
        self.assertEqual(client.cache, {})

    def test_corrupted_toml_file_handling(self):
        """Test handling of corrupted TOML file."""
        corrupted_toml = os.path.join(self.test_dir, "corrupted.toml")

        with open(corrupted_toml, "w") as f:
            f.write("invalid toml content [[[")

        # Should handle corrupted TOML gracefully
        result = package_analysis.load_toml(corrupted_toml)
        self.assertEqual(result, {})

    def test_invalid_custom_install_json(self):
        """Test handling of invalid custom installation JSON."""
        invalid_json = os.path.join(self.test_dir, "invalid.json")

        with open(invalid_json, "w") as f:
            f.write("invalid json content")

        # Should handle invalid JSON gracefully
        result = load_custom_installations(invalid_json)
        self.assertEqual(result, {})

    def test_empty_package_list_handling(self):
        """Test handling of empty package lists in file generation."""
        file_generator = PackageFileGenerator()

        # Empty package lists should generate valid but potentially empty files
        empty_packages = {}
        empty_toml = {}

        brewfile = file_generator.generate_brewfile(empty_packages, empty_toml)
        self.assertIsInstance(brewfile, str)
        self.assertIn("# Platform-specific packages", brewfile)

        archfile = file_generator.generate_archfile(empty_packages, empty_toml)
        self.assertIsInstance(archfile, str)

        customfile = file_generator.generate_customfile(empty_packages, empty_toml)
        self.assertIsInstance(customfile, str)
        self.assertIn("# Custom installation commands", customfile)


if __name__ == "__main__":
    # Ensure we're running from the correct directory
    os.chdir(Path(__file__).parent.parent)

    # Run the tests
    unittest.main(verbosity=2)
