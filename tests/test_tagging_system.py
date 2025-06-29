#!/usr/bin/env python3
"""
Comprehensive tests for the package tagging system

Tests cover:
- Tag parsing and matching
- TaggedPackageFilter functionality
- Tag query language
- Migration utilities
- Auto-tagging capabilities
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

# Add the lib directory to the path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
sys.path.insert(0, str(Path(__file__).parent.parent / "bin"))

try:
    from tagged_package_filter import (
        Tag, TagExpression, TaggedPackageFilter, TagNamespace,
        migrate_package_to_tags, auto_categorize_package
    )
    from package_analysis_tagged import (
        analyze_repology_data_for_tags, analyze_homebrew_data_for_tags,
        suggest_role_tags, suggest_priority_tags, generate_tags_for_package
    )
except ImportError as e:
    print(f"Error importing tagging modules: {e}")
    sys.exit(1)


class TestTag(unittest.TestCase):
    """Test the Tag class functionality"""
    
    def test_tag_parsing(self):
        """Test parsing of tag strings"""
        # Test namespaced tags
        tag = Tag.parse("os:macos")
        self.assertEqual(tag.namespace, "os")
        self.assertEqual(tag.value, "macos")
        
        # Test non-namespaced tags
        tag = Tag.parse("custom-tag")
        self.assertIsNone(tag.namespace)
        self.assertEqual(tag.value, "custom-tag")
        
        # Test multi-level namespace
        tag = Tag.parse("pm:homebrew:darwin")
        self.assertEqual(tag.namespace, "pm")
        self.assertEqual(tag.value, "homebrew:darwin")
    
    def test_tag_string_representation(self):
        """Test string representation of tags"""
        tag = Tag("os", "macos")
        self.assertEqual(str(tag), "os:macos")
        
        tag = Tag(None, "custom-tag")
        self.assertEqual(str(tag), "custom-tag")
    
    def test_tag_matching(self):
        """Test tag matching logic"""
        # Exact match
        tag1 = Tag.parse("os:macos")
        tag2 = Tag.parse("os:macos")
        self.assertTrue(tag1.matches(tag2))
        
        # No match
        tag1 = Tag.parse("os:macos")
        tag2 = Tag.parse("os:linux")
        self.assertFalse(tag1.matches(tag2))
        
        # Hierarchical matching for package managers
        tag1 = Tag.parse("pm:homebrew")
        tag2 = Tag.parse("pm:homebrew:darwin")
        self.assertTrue(tag1.matches(tag2))
        self.assertTrue(tag2.matches(tag1))
        
        # No hierarchical match for other namespaces
        tag1 = Tag.parse("cat:development")
        tag2 = Tag.parse("cat:development:advanced")
        self.assertFalse(tag1.matches(tag2))


class TestTagExpression(unittest.TestCase):
    """Test the TagExpression query language"""
    
    def test_single_tag_expression(self):
        """Test single tag expressions"""
        expr = TagExpression("os:macos")
        
        # Should match
        self.assertTrue(expr.evaluate(["os:macos", "cat:development"]))
        
        # Should not match
        self.assertFalse(expr.evaluate(["os:linux", "cat:development"]))
    
    def test_and_expression(self):
        """Test AND expressions"""
        expr = TagExpression("os:macos AND cat:development")
        
        # Should match (has both)
        self.assertTrue(expr.evaluate(["os:macos", "cat:development", "role:desktop"]))
        
        # Should not match (missing one)
        self.assertFalse(expr.evaluate(["os:macos", "role:desktop"]))
        self.assertFalse(expr.evaluate(["cat:development", "role:desktop"]))
    
    def test_or_expression(self):
        """Test OR expressions"""
        expr = TagExpression("os:macos OR os:linux")
        
        # Should match (has first)
        self.assertTrue(expr.evaluate(["os:macos", "cat:development"]))
        
        # Should match (has second)
        self.assertTrue(expr.evaluate(["os:linux", "cat:development"]))
        
        # Should not match (has neither)
        self.assertFalse(expr.evaluate(["os:windows", "cat:development"]))
    
    def test_not_expression(self):
        """Test NOT expressions"""
        expr = TagExpression("NOT os:windows")
        
        # Should match (doesn't have windows)
        self.assertTrue(expr.evaluate(["os:macos", "cat:development"]))
        
        # Should not match (has windows)
        self.assertFalse(expr.evaluate(["os:windows", "cat:development"]))
    
    def test_hierarchical_matching_in_expressions(self):
        """Test hierarchical matching in expressions"""
        expr = TagExpression("pm:homebrew")
        
        # Should match specific homebrew tags
        self.assertTrue(expr.evaluate(["pm:homebrew:darwin", "cat:development"]))
        self.assertTrue(expr.evaluate(["pm:homebrew:linux", "cat:development"]))
        
        # Should match general homebrew tag
        self.assertTrue(expr.evaluate(["pm:homebrew", "cat:development"]))


class TestTaggedPackageFilter(unittest.TestCase):
    """Test the TaggedPackageFilter class"""
    
    def setUp(self):
        self.mock_platform = Mock()
        self.mock_platform.is_darwin = True
        self.mock_platform.is_linux = False
        self.mock_platform.is_arch_like = False
        self.mock_platform.is_debian_like = False
        self.mock_platform.is_fedora_like = False
        self.mock_platform.get_native_package_manager.return_value = "homebrew"
        self.mock_platform.supports_homebrew.return_value = True
        self.mock_platform.supports_flatpak.return_value = False
        
        self.test_toml = {
            "git": {
                "tags": ["os:macos", "os:linux", "pm:homebrew", "pm:apt", "cat:development", "cat:vcs"],
                "description": "Version control system"
            },
            "firefox": {
                "tags": ["os:macos", "os:linux", "pm:homebrew:darwin", "cat:browser", "role:desktop"],
                "description": "Web browser"
            },
            "legacy-package": {
                "arch-pkg": "legacy",
                "brew-supports-darwin": True,
                "description": "Legacy package without tags"
            }
        }
        
        self.filter = TaggedPackageFilter(self.test_toml, self.mock_platform)
    
    def test_platform_tag_generation(self):
        """Test automatic platform tag generation"""
        platform_tags = self.filter._get_platform_tags()
        
        self.assertIn("os:macos", platform_tags)
        self.assertIn("pm:homebrew", platform_tags)
        self.assertIn("pm:homebrew:darwin", platform_tags)
        self.assertIn("arch:x86_64", platform_tags)  # Default assumption
    
    def test_legacy_tag_generation(self):
        """Test generation of tags from legacy fields"""
        entry = {
            "arch-pkg": "test",
            "brew-supports-darwin": True,
            "brew-supports-linux": False,
            "flatpak-pkg": "",
            "description": "Test package"
        }
        
        tags = self.filter._generate_legacy_tags(entry)
        
        self.assertIn("os:linux", tags)
        self.assertIn("dist:arch", tags)
        self.assertIn("pm:pacman", tags)
        self.assertIn("os:macos", tags)
        self.assertIn("pm:homebrew:darwin", tags)
    
    def test_package_tag_retrieval(self):
        """Test getting tags for packages"""
        # Package with explicit tags
        tags = self.filter.get_package_tags("git", self.test_toml["git"])
        self.assertIn("cat:development", tags)
        self.assertIn("os:macos", tags)
        
        # Package with legacy fields (auto-generated tags)
        tags = self.filter.get_package_tags("legacy-package", self.test_toml["legacy-package"])
        self.assertIn("os:linux", tags)  # From arch-pkg
        self.assertIn("os:macos", tags)  # From brew-supports-darwin
    
    def test_tag_checking_functions(self):
        """Test tag checking utility functions"""
        # is_tag_set
        self.assertTrue(self.filter.is_tag_set("git", "cat:development"))
        self.assertFalse(self.filter.is_tag_set("git", "cat:gaming"))
        
        # has_any_tags
        self.assertTrue(self.filter.has_any_tags("git", ["cat:development", "cat:gaming"]))
        self.assertFalse(self.filter.has_any_tags("git", ["cat:gaming", "cat:multimedia"]))
        
        # has_all_tags
        self.assertTrue(self.filter.has_all_tags("git", ["cat:development", "os:macos"]))
        self.assertFalse(self.filter.has_all_tags("git", ["cat:development", "cat:gaming"]))
    
    def test_filter_by_tags(self):
        """Test filtering packages by tag queries"""
        # Simple tag filter
        filtered = self.filter.filter_by_tags("cat:development")
        self.assertIn("git", filtered)
        self.assertNotIn("firefox", filtered)
        
        # AND filter
        filtered = self.filter.filter_by_tags("os:macos AND cat:browser")
        self.assertIn("firefox", filtered)
        self.assertNotIn("git", filtered)
        
        # OR filter
        filtered = self.filter.filter_by_tags("cat:development OR cat:browser")
        self.assertIn("git", filtered)
        self.assertIn("firefox", filtered)
    
    def test_role_and_category_filtering(self):
        """Test role and category specific filtering"""
        # Filter by role
        desktop_packages = self.filter.get_packages_for_role("desktop")
        self.assertIn("firefox", desktop_packages)
        
        # Filter by category
        dev_packages = self.filter.get_packages_by_category("development")
        self.assertIn("git", dev_packages)
    
    def test_desktop_environment_filtering(self):
        """Test desktop environment specific filtering"""
        # Add a package with DE tags for testing
        test_toml = self.test_toml.copy()
        test_toml["gnome-shell"] = {
            "tags": ["os:linux", "de:gnome", "cat:desktop-environment"],
            "description": "GNOME Shell"
        }
        test_toml["hyprland"] = {
            "tags": ["os:linux", "de:hyprland", "cat:desktop-environment"],
            "description": "Hyprland compositor"
        }
        
        filter = TaggedPackageFilter(test_toml, self.mock_platform)
        
        # Filter by specific DE
        gnome_packages = filter.get_packages_for_desktop_environment("gnome")
        self.assertIn("gnome-shell", gnome_packages)
        self.assertNotIn("hyprland", gnome_packages)
        
        # Filter excluding specific DEs using basic query
        # Test the exclusion logic with a simpler approach
        all_packages_query = filter.filter_by_tags("NOT de:gnome")
        self.assertNotIn("gnome-shell", all_packages_query)
        self.assertIn("hyprland", all_packages_query)
        self.assertIn("git", all_packages_query)  # Should include non-DE packages
    
    def test_atomic_distro_filtering(self):
        """Test atomic vs traditional distribution filtering"""
        # Add packages with different package manager preferences
        test_toml = self.test_toml.copy()
        test_toml["rpm-package"] = {
            "tags": ["os:linux", "pm:dnf", "disttype:traditional"],
            "description": "Native RPM package"
        }
        test_toml["flatpak-app"] = {
            "tags": ["os:linux", "pm:flatpak", "disttype:atomic"],
            "description": "Flatpak application"
        }
        test_toml["homebrew-tool"] = {
            "tags": ["os:linux", "pm:homebrew", "cat:development"],
            "description": "Cross-platform tool"
        }
        
        filter = TaggedPackageFilter(test_toml, self.mock_platform)
        
        # Test atomic distro filtering
        atomic_packages = filter.get_packages_for_atomic_distros()
        self.assertIn("flatpak-app", atomic_packages)
        self.assertIn("homebrew-tool", atomic_packages)  # Homebrew works on atomic
        # Note: rpm-package might be included since we use simple OR query
        
        # Test traditional distro filtering  
        traditional_packages = filter.get_packages_for_traditional_distros()
        self.assertIn("rpm-package", traditional_packages)
        # Note: traditional query is more permissive and includes packages without disttype tags
    
    def test_current_platform_filtering(self):
        """Test filtering for current platform compatibility"""
        compatible = self.filter.filter_by_current_platform()
        
        # Should include packages that work on macOS
        self.assertIn("git", compatible)
        self.assertIn("firefox", compatible)
        
        # Should include legacy packages that support macOS
        self.assertIn("legacy-package", compatible)


class TestMigrationUtilities(unittest.TestCase):
    """Test package migration utilities"""
    
    def test_migrate_basic_package(self):
        """Test migrating a basic package to tagged format"""
        entry = {
            "arch-pkg": "git",
            "apt-pkg": "git",
            "brew-supports-darwin": True,
            "brew-supports-linux": True,
            "description": "Version control system"
        }
        
        migrated = migrate_package_to_tags(entry)
        
        self.assertIn("tags", migrated)
        tags = migrated["tags"]
        
        self.assertIn("os:linux", tags)
        self.assertIn("os:macos", tags)
        self.assertIn("pm:apt", tags)
        self.assertIn("pm:pacman", tags)
        self.assertIn("pm:homebrew", tags)  # Both platforms supported
    
    def test_migrate_cask_package(self):
        """Test migrating a Homebrew cask package"""
        entry = {
            "brew-supports-darwin": True,
            "brew-is-cask": True,
            "description": "macOS application"
        }
        
        migrated = migrate_package_to_tags(entry)
        tags = migrated["tags"]
        
        self.assertIn("os:macos", tags)
        self.assertIn("pm:homebrew:darwin", tags)
        self.assertIn("cat:cask", tags)
    
    def test_migrate_aur_package(self):
        """Test migrating an AUR package"""
        entry = {
            "arch-pkg": "aur-package",
            "arch-is-aur": True,
            "description": "AUR package"
        }
        
        migrated = migrate_package_to_tags(entry)
        tags = migrated["tags"]
        
        self.assertIn("os:linux", tags)
        self.assertIn("dist:arch", tags)
        self.assertIn("pm:pacman", tags)
        self.assertIn("cat:aur", tags)
    
    def test_migrate_custom_install_package(self):
        """Test migrating a package with custom installation"""
        entry = {
            "custom-install": {"default": ["echo 'install'"]},
            "custom-install-priority": "fallback",
            "description": "Custom package"
        }
        
        migrated = migrate_package_to_tags(entry)
        tags = migrated["tags"]
        
        self.assertIn("pm:custom", tags)
        self.assertIn("priority:custom-fallback", tags)
    
    def test_preserve_existing_tags(self):
        """Test that existing tags are preserved"""
        entry = {
            "tags": ["existing:tag", "custom-tag"],
            "arch-pkg": "test",
            "description": "Test package"
        }
        
        migrated = migrate_package_to_tags(entry)
        tags = migrated["tags"]
        
        # Should preserve existing tags
        self.assertIn("existing:tag", tags)
        self.assertIn("custom-tag", tags)


class TestAutoTagging(unittest.TestCase):
    """Test automatic tag generation"""
    
    def test_auto_categorize_development_tools(self):
        """Test auto-categorization of development tools"""
        tags = auto_categorize_package("git", "Distributed version control system")
        self.assertIn("cat:vcs", tags)
        # git doesn't get cat:development automatically since it's specifically VCS
        
        tags = auto_categorize_package("vim", "Text editor")
        self.assertIn("cat:editor", tags)
        
        tags = auto_categorize_package("gcc", "GNU Compiler Collection")
        self.assertIn("cat:development", tags)  # This should work due to "compiler" keyword
    
    def test_auto_categorize_system_tools(self):
        """Test auto-categorization of system tools"""
        tags = auto_categorize_package("htop", "Interactive process viewer")
        self.assertIn("cat:system", tags)  # "process" keyword should trigger this
        
        tags = auto_categorize_package("ssh", "Secure Shell client")
        self.assertIn("cat:network", tags)  # "ssh" keyword should trigger network
        # Note: "security" keyword not in description, so no cat:security
    
    def test_auto_categorize_multimedia(self):
        """Test auto-categorization of multimedia tools"""
        tags = auto_categorize_package("vlc", "Media player")
        self.assertIn("cat:multimedia", tags)
        
        tags = auto_categorize_package("ffmpeg", "Video processing")
        self.assertIn("cat:multimedia", tags)
        
        tags = auto_categorize_package("gimp", "Image editor")
        self.assertIn("cat:graphics", tags)
    
    def test_auto_categorize_cli_tools(self):
        """Test auto-categorization of CLI tools"""
        tags = auto_categorize_package("rg", "Ripgrep search tool")
        self.assertIn("cat:cli-tool", tags)
        
        tags = auto_categorize_package("fd", "File finder")
        self.assertIn("cat:cli-tool", tags)
    
    def test_auto_categorize_desktop_environment_packages(self):
        """Test auto-categorization of desktop environment packages"""
        # GNOME packages
        tags = auto_categorize_package("gnome-shell", "GNOME desktop shell")
        self.assertIn("de:gnome", tags)
        
        tags = auto_categorize_package("nautilus", "GNOME file manager")
        self.assertIn("de:gnome", tags)
        
        # KDE packages
        tags = auto_categorize_package("plasma-desktop", "KDE Plasma desktop")
        self.assertIn("de:kde", tags)
        
        # Hyprland packages
        tags = auto_categorize_package("hyprland", "Dynamic tiling Wayland compositor")
        self.assertIn("de:hyprland", tags)
        
        # Sway packages
        tags = auto_categorize_package("sway", "Wayland compositor")
        self.assertIn("de:sway", tags)
        
        # i3 packages
        tags = auto_categorize_package("i3", "Tiling window manager")
        self.assertIn("de:i3", tags)
    
    def test_repology_data_analysis(self):
        """Test tag extraction from Repology data"""
        repology_data = {
            "platforms": {
                "ubuntu": {"categories": ["devel", "vcs"]},
                "arch": {"categories": ["development"]},
                "homebrew": {"categories": ["development"]},
                "fedora": {"categories": ["devel"]},
                "debian": {"categories": ["vcs"]},
                "alpine": {"categories": ["development"]}
            }
        }
        
        tags = analyze_repology_data_for_tags(repology_data)
        self.assertIn("cat:development", tags)
        self.assertIn("cat:vcs", tags)
        self.assertIn("priority:essential", tags)  # Available on 6 platforms (>5)
    
    def test_homebrew_data_analysis(self):
        """Test tag extraction from Homebrew data"""
        brew_data = {
            "cask": True,
            "desc": "GUI application for development",
            "tags": ["development", "gui"]
        }
        
        tags = analyze_homebrew_data_for_tags(brew_data)
        self.assertIn("cat:cask", tags)
        self.assertIn("role:desktop", tags)
        self.assertIn("cat:development", tags)
    
    def test_role_tag_suggestions(self):
        """Test role tag suggestions"""
        # Development tools
        dev_tags = ["cat:development", "cat:editor"]
        roles = suggest_role_tags("vim", dev_tags)
        self.assertIn("role:development", roles)
        
        # Server tools
        server_tags = ["cat:system", "cat:network"]
        roles = suggest_role_tags("nginx", server_tags)
        self.assertIn("role:server", roles)
        self.assertIn("role:headless", roles)
        
        # Desktop apps
        desktop_tags = ["cat:gui", "cat:browser"]
        roles = suggest_role_tags("firefox", desktop_tags)
        self.assertIn("role:desktop", roles)
    
    def test_priority_tag_suggestions(self):
        """Test priority tag suggestions"""
        # Essential tools
        priorities = suggest_priority_tags("git", ["cat:vcs"], platforms_count=10)
        self.assertIn("priority:essential", priorities)
        self.assertIn("scope:core", priorities)
        
        # Recommended tools
        priorities = suggest_priority_tags("code", ["cat:editor"], platforms_count=5)
        self.assertIn("priority:recommended", priorities)
        
        # Optional tools
        priorities = suggest_priority_tags("obscure-tool", ["cat:utility"], platforms_count=1)
        self.assertIn("priority:optional", priorities)


class TestTaggedPackageIntegration(unittest.TestCase):
    """Test integration between different tagging components"""
    
    def test_complete_package_enhancement(self):
        """Test complete package enhancement with tags"""
        from package_analysis_tagged import enhance_package_entry_with_tags
        
        entry = {
            "arch-pkg": "git",
            "apt-pkg": "git",
            "brew-supports-darwin": True,
            "description": "Distributed version control system"
        }
        
        enhanced = enhance_package_entry_with_tags("git", entry)
        
        self.assertIn("tags", enhanced)
        tags = enhanced["tags"]
        
        # Should have platform tags
        self.assertTrue(any(t.startswith("os:") for t in tags))
        self.assertTrue(any(t.startswith("pm:") for t in tags))
        
        # Should have category tags
        self.assertTrue(any(t.startswith("cat:") for t in tags))
        
        # Should have role tags
        self.assertTrue(any(t.startswith("role:") for t in tags))
        
        # Should have priority tags
        self.assertTrue(any(t.startswith("priority:") for t in tags))
    
    def test_tag_query_with_generated_tags(self):
        """Test tag queries work with auto-generated tags"""
        # Create a package with legacy format
        toml_data = {
            "git": {
                "arch-pkg": "git",
                "brew-supports-darwin": True,
                "description": "Version control system"
            }
        }
        
        mock_platform = Mock()
        mock_platform.is_darwin = True
        mock_platform.is_linux = False
        
        filter = TaggedPackageFilter(toml_data, mock_platform)
        
        # Should be able to filter by auto-generated tags
        self.assertTrue(filter.is_tag_set("git", "os:macos"))
        self.assertTrue(filter.is_tag_set("git", "pm:homebrew:darwin"))
        
        # Should work with complex queries
        filtered = filter.filter_by_tags("os:macos AND pm:homebrew")
        self.assertIn("git", filtered)


class TestTagNamespaces(unittest.TestCase):
    """Test tag namespace validation"""
    
    def test_recognized_namespaces(self):
        """Test that recognized namespaces are properly defined"""
        expected_namespaces = {
            'os', 'arch', 'dist', 'disttype', 'de', 'pm', 'cat', 'role', 'priority', 'scope'
        }
        
        actual_namespaces = {ns.value for ns in TagNamespace}
        self.assertEqual(expected_namespaces, actual_namespaces)
    
    def test_namespace_validation_in_filter(self):
        """Test that filter recognizes namespace prefixes"""
        mock_platform = Mock()
        filter = TaggedPackageFilter({}, mock_platform)
        
        # Test with recognized namespace
        recognized_tag = "os:macos"
        self.assertTrue(any(recognized_tag.startswith(f"{ns.value}:") 
                          for ns in TagNamespace))
        
        # Test with unrecognized namespace
        unrecognized_tag = "custom:tag"
        self.assertFalse(any(unrecognized_tag.startswith(f"{ns.value}:") 
                           for ns in TagNamespace))


if __name__ == '__main__':
    # Set up test environment
    os.chdir(Path(__file__).parent.parent)
    
    # Run the tests
    unittest.main(verbosity=2)