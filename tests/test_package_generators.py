#!/usr/bin/env python3
"""
Unit tests for package_generators.py

These tests verify the functionality of package generation including:
- Platform detection
- Package filtering logic
- Custom installation command resolution
- Package file generation (Brewfile, Archfile, etc.)
- Hierarchical custom installation support
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Add the bin directory to the path so we can import package_generators
sys.path.insert(0, str(Path(__file__).parent.parent / "bin"))

try:
    import package_generators
    from package_generators import (
        PlatformDetector,
        PackageFilter,
        PackageFileGenerator,
        _has_any_packages,
        load_toml
    )
except ImportError as e:
    print(f"Error importing package_generators: {e}")
    sys.exit(1)


class TestPlatformDetector(unittest.TestCase):
    """Test platform detection functionality."""
    
    @patch('package_generators.platform.system')
    @patch('package_generators.os.path.exists')
    def test_darwin_detection(self, mock_exists, mock_system):
        """Test macOS platform detection."""
        mock_system.return_value = 'Darwin'
        mock_exists.return_value = True  # /opt/homebrew exists
        
        detector = PlatformDetector()
        
        self.assertTrue(detector.is_darwin)
        self.assertFalse(detector.is_linux)
        self.assertTrue(detector.supports_homebrew())
        self.assertFalse(detector.supports_flatpak())
    
    @patch('package_generators.platform.system')
    @patch('package_generators.os.path.exists')
    def test_linux_detection(self, mock_exists, mock_system):
        """Test Linux platform detection."""
        mock_system.return_value = 'Linux'
        mock_exists.side_effect = lambda path: path == '/etc/os-release'
        
        with patch('builtins.open', mock_open_os_release('ubuntu')):
            detector = PlatformDetector()
        
        self.assertFalse(detector.is_darwin)
        self.assertTrue(detector.is_linux)
        self.assertTrue(detector.is_debian_like)
        self.assertFalse(detector.is_arch_like)
        self.assertFalse(detector.is_fedora_like)
    
    @patch('package_generators.platform.system')
    @patch('package_generators.os.path.exists')
    def test_arch_detection(self, mock_exists, mock_system):
        """Test Arch Linux detection."""
        mock_system.return_value = 'Linux'
        mock_exists.side_effect = lambda path: path == '/etc/os-release'
        
        with patch('builtins.open', mock_open_os_release('arch')):
            detector = PlatformDetector()
        
        self.assertTrue(detector.is_linux)
        self.assertTrue(detector.is_arch_like)
        self.assertFalse(detector.is_debian_like)
        self.assertEqual(detector.get_native_package_manager(), "arch")
    
    @patch('package_generators.platform.system')
    @patch('package_generators.os.path.exists')
    def test_fedora_detection(self, mock_exists, mock_system):
        """Test Fedora detection."""
        mock_system.return_value = 'Linux'
        mock_exists.side_effect = lambda path: path == '/etc/os-release'
        
        with patch('builtins.open', mock_open_os_release('fedora')):
            detector = PlatformDetector()
        
        self.assertTrue(detector.is_linux)
        self.assertTrue(detector.is_fedora_like)
        self.assertFalse(detector.is_debian_like)
        self.assertEqual(detector.get_native_package_manager(), "fedora")


class TestPackageFilter(unittest.TestCase):
    """Test package filtering logic."""
    
    def setUp(self):
        self.mock_platform = Mock(spec=PlatformDetector)
        self.mock_platform.is_darwin = False
        self.mock_platform.is_linux = True
        self.mock_platform.is_arch_like = True
        self.mock_platform.is_debian_like = False
        self.mock_platform.is_fedora_like = False
        self.mock_platform.get_native_package_manager.return_value = "arch"
        self.mock_platform.supports_homebrew.return_value = False
        self.mock_platform.supports_flatpak.return_value = True
        
        self.test_toml = {
            "standard-package": {
                "arch-pkg": "standard-pkg",
                "apt-pkg": "standard-pkg",
                "flatpak-pkg": "",
                "brew-supports-darwin": True,
                "brew-supports-linux": False,
                "custom-install": ""
            },
            "flatpak-package": {
                "arch-pkg": "",
                "apt-pkg": "",
                "flatpak-pkg": "org.test.App",
                "brew-supports-darwin": False,
                "brew-supports-linux": False,
                "custom-install": ""
            },
            "custom-always": {
                "arch-pkg": "test-pkg",
                "apt-pkg": "test-pkg",
                "flatpak-pkg": "",
                "brew-supports-darwin": True,
                "brew-supports-linux": True,
                "custom-install": {
                    "is_arch_like": ["yay -S custom-pkg"],
                    "default": ["echo 'fallback'"]
                },
                "custom-install-priority": "always"
            },
            "custom-fallback": {
                "arch-pkg": "",
                "apt-pkg": "",
                "flatpak-pkg": "",
                "brew-supports-darwin": False,
                "brew-supports-linux": False,
                "custom-install": {
                    "default": ["echo 'only option'"]
                },
                "custom-install-priority": "fallback"
            }
        }
        
        self.filter = PackageFilter(self.test_toml, self.mock_platform)
    
    def test_should_use_native_package(self):
        """Test native package detection."""
        self.assertTrue(self.filter.should_use_native_package("standard-package", self.test_toml["standard-package"]))
        self.assertFalse(self.filter.should_use_native_package("flatpak-package", self.test_toml["flatpak-package"]))
    
    def test_should_use_flatpak(self):
        """Test Flatpak package detection."""
        self.assertTrue(self.filter.should_use_flatpak("flatpak-package", self.test_toml["flatpak-package"]))
        self.assertFalse(self.filter.should_use_flatpak("standard-package", self.test_toml["standard-package"]))
    
    def test_should_use_custom_install_always(self):
        """Test custom installation with always priority."""
        self.assertTrue(self.filter.should_use_custom_install("custom-always", self.test_toml["custom-always"]))
    
    def test_should_use_custom_install_fallback(self):
        """Test custom installation with fallback priority."""
        self.assertTrue(self.filter.should_use_custom_install("custom-fallback", self.test_toml["custom-fallback"]))
    
    def test_get_custom_install_commands(self):
        """Test platform-specific custom installation command resolution."""
        # Test platform-specific commands
        commands = self.filter.get_custom_install_commands(self.test_toml["custom-always"])
        self.assertEqual(commands, ["yay -S custom-pkg"])
        
        # Test fallback to default
        commands = self.filter.get_custom_install_commands(self.test_toml["custom-fallback"])
        self.assertEqual(commands, ["echo 'only option'"])
        
        # Test empty commands
        commands = self.filter.get_custom_install_commands({"custom-install": {}})
        self.assertEqual(commands, [])
    
    def test_get_filtered_packages_native(self):
        """Test filtering for native packages."""
        filtered = self.filter.get_filtered_packages("native")
        
        self.assertIn("standard-package", filtered)
        self.assertEqual(filtered["standard-package"], "standard-pkg")
        self.assertNotIn("flatpak-package", filtered)
        self.assertNotIn("custom-always", filtered)  # Custom overrides native
    
    def test_get_filtered_packages_flatpak(self):
        """Test filtering for Flatpak packages."""
        filtered = self.filter.get_filtered_packages("flatpak")
        
        self.assertIn("flatpak-package", filtered)
        self.assertEqual(filtered["flatpak-package"], "org.test.App")
        self.assertNotIn("standard-package", filtered)
    
    def test_get_filtered_packages_custom(self):
        """Test filtering for custom installation packages."""
        filtered = self.filter.get_filtered_packages("custom")
        
        self.assertIn("custom-always", filtered)
        self.assertIn("custom-fallback", filtered)
        self.assertEqual(filtered["custom-always"], ["yay -S custom-pkg"])
        self.assertEqual(filtered["custom-fallback"], ["echo 'only option'"])


class TestPackageFileGenerator(unittest.TestCase):
    """Test package file generation."""
    
    def setUp(self):
        self.generator = PackageFileGenerator()
        self.test_toml = {
            "regular-package": {
                "brew-is-cask": False,
                "description": "Regular package"
            },
            "cask-package": {
                "brew-is-cask": True,
                "description": "Cask package"
            },
            "aur-package": {
                "arch-is-aur": True,
                "description": "AUR package"
            },
            "regular-arch-package": {
                "arch-is-aur": False,
                "description": "Regular Arch package"
            }
        }
    
    def test_generate_brewfile(self):
        """Test Brewfile generation."""
        packages = {
            "regular-package": "regular-pkg",
            "cask-package": "cask-pkg"
        }
        
        result = self.generator.generate_brewfile(packages, self.test_toml)
        
        self.assertIn('brew "regular-pkg"', result)
        self.assertIn('cask "cask-pkg"', result)
    
    def test_generate_archfile(self):
        """Test Archfile generation with AUR comments."""
        packages = {
            "aur-package": "aur-pkg",
            "regular-arch-package": "arch-pkg"
        }
        
        result = self.generator.generate_archfile(packages, self.test_toml)
        
        self.assertIn("aur-pkg  # AUR", result)
        self.assertIn("arch-pkg\n", result)
        self.assertNotIn("arch-pkg  # AUR", result)
    
    def test_generate_simple_list(self):
        """Test simple package list generation."""
        packages = {
            "package1": "pkg1",
            "package2": "pkg2"
        }
        
        result = self.generator.generate_simple_list(packages)
        
        self.assertIn("pkg1", result)
        self.assertIn("pkg2", result)
        lines = result.strip().split('\n')
        self.assertEqual(len(lines), 2)
    
    def test_generate_customfile(self):
        """Test custom installation file generation."""
        packages = {
            "test-package": ["echo 'step1'", "echo 'step2'"],
            "simple-package": ["echo 'simple'"]
        }
        
        test_toml = {
            "test-package": {
                "description": "Test package",
                "requires-confirmation": True,
                "install-condition": "command -v echo"
            },
            "simple-package": {
                "description": "Simple package"
            }
        }
        
        result = self.generator.generate_customfile(packages, test_toml)
        
        self.assertIn("# Custom installation commands", result)
        self.assertIn("test-package|echo 'step1'|echo 'step2'", result)
        self.assertIn("simple-package|echo 'simple'", result)
        self.assertIn("# Requires user confirmation", result)
        self.assertIn("# Condition: command -v echo", result)


class TestHasAnyPackages(unittest.TestCase):
    """Test package availability detection."""
    
    def test_has_standard_packages(self):
        """Test detecting standard package availability."""
        entry_with_packages = {
            "arch-pkg": "test-pkg",
            "apt-pkg": "",
            "flatpak-pkg": "",
            "custom-install": ""
        }
        
        entry_without_packages = {
            "arch-pkg": "",
            "apt-pkg": "",
            "flatpak-pkg": "",
            "custom-install": ""
        }
        
        self.assertTrue(_has_any_packages(entry_with_packages))
        self.assertFalse(_has_any_packages(entry_without_packages))
    
    def test_has_custom_install(self):
        """Test detecting custom installation availability."""
        entry_with_custom = {
            "arch-pkg": "",
            "apt-pkg": "",
            "flatpak-pkg": "",
            "custom-install": {"default": ["echo 'test'"]}
        }
        
        self.assertTrue(_has_any_packages(entry_with_custom))
    
    def test_has_homebrew_availability(self):
        """Test detecting Homebrew availability."""
        entry_with_brew = {
            "arch-pkg": "",
            "apt-pkg": "",
            "flatpak-pkg": "",
            "custom-install": "",
            "brew-supports-darwin": True
        }
        
        self.assertTrue(_has_any_packages(entry_with_brew))


# Helper functions for mocking
def mock_open_os_release(distro_id):
    """Create a mock open function that returns os-release content."""
    content = f'ID="{distro_id}"\nNAME="{distro_id.title()}"\n'
    
    def mock_open_func(*args, **kwargs):
        from unittest.mock import mock_open
        return mock_open(read_data=content)(*args, **kwargs)
    
    return mock_open_func


if __name__ == '__main__':
    # Ensure we're running from the correct directory
    os.chdir(Path(__file__).parent.parent)
    
    # Run the tests
    unittest.main(verbosity=2)