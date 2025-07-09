#!/usr/bin/env python3
"""
Tests for TOML formatting functionality

Tests cover:
- One tag per line formatting
- Alphabetical tag ordering
- Description field handling (only when non-empty)
- Single tag vs multiple tag formatting
- Round-trip formatting consistency
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

# Add the bin directory to the path
sys.path.insert(0, str(Path(__file__).parent.parent / "bin"))

try:
    from package_analysis_cli import write_toml
    from reformat_toml_tags import format_tags, main as reformat_main
    import toml
except ImportError as e:
    print(f"Error importing modules: {e}")
    sys.exit(1)


class TestTomlFormatting(unittest.TestCase):
    """Test TOML formatting functionality"""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.test_toml_path = os.path.join(self.temp_dir, "test.toml")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.temp_dir)

    def test_format_tags_single_tag(self):
        """Test formatting of single tag"""
        tags = ["cat:utility"]
        result = format_tags(tags)
        expected = '["cat:utility"]'
        self.assertEqual(result, expected)

    def test_format_tags_multiple_tags(self):
        """Test formatting of multiple tags with alphabetization"""
        tags = ["pm:homebrew", "cat:cli-tool", "os:macos", "priority:recommended"]
        result = format_tags(tags)
        expected_lines = [
            "[",
            '    "cat:cli-tool",',
            '    "os:macos",',
            '    "pm:homebrew",',
            '    "priority:recommended"',
            "]"
        ]
        expected = "\n".join(expected_lines)
        self.assertEqual(result, expected)

    def test_format_tags_empty_list(self):
        """Test formatting of empty tag list"""
        tags = []
        result = format_tags(tags)
        expected = "[]"
        self.assertEqual(result, expected)

    def test_format_tags_alphabetical_ordering(self):
        """Test that tags are properly alphabetized"""
        tags = ["z-last", "a-first", "m-middle", "b-second"]
        result = format_tags(tags)
        expected_lines = [
            "[",
            '    "a-first",',
            '    "b-second",',
            '    "m-middle",',
            '    "z-last"',
            "]"
        ]
        expected = "\n".join(expected_lines)
        self.assertEqual(result, expected)

    def test_write_toml_with_description(self):
        """Test that descriptions are written when present"""
        data = {
            "test-package": {
                "description": "Test package description",
                "tags": ["cat:utility", "os:linux"]
            }
        }
        
        write_toml(data, self.test_toml_path)
        
        with open(self.test_toml_path, 'r') as f:
            content = f.read()
            
        # Check that description is present
        self.assertIn('description = "Test package description"', content)
        # Check that tags are formatted correctly
        self.assertIn('tags = [', content)
        self.assertIn('    "cat:utility",', content)
        self.assertIn('    "os:linux"', content)

    def test_write_toml_without_description(self):
        """Test that description field is omitted when empty"""
        data = {
            "test-package": {
                "tags": ["cat:utility", "os:linux"]
            }
        }
        
        write_toml(data, self.test_toml_path)
        
        with open(self.test_toml_path, 'r') as f:
            content = f.read()
            
        # Check that description is not present
        self.assertNotIn('description =', content)
        # Check that tags are still formatted correctly
        self.assertIn('tags = [', content)

    def test_write_toml_empty_description_omitted(self):
        """Test that empty description field is omitted"""
        data = {
            "test-package": {
                "description": "",
                "tags": ["cat:utility"]
            }
        }
        
        write_toml(data, self.test_toml_path)
        
        with open(self.test_toml_path, 'r') as f:
            content = f.read()
            
        # Check that description is not present
        self.assertNotIn('description =', content)

    def test_write_toml_single_tag_format(self):
        """Test formatting of single tag in TOML"""
        data = {
            "test-package": {
                "tags": ["cat:utility"]
            }
        }
        
        write_toml(data, self.test_toml_path)
        
        with open(self.test_toml_path, 'r') as f:
            content = f.read()
            
        # Single tag should be on one line
        self.assertIn('tags = ["cat:utility"]', content)

    def test_write_toml_multiple_packages(self):
        """Test formatting of multiple packages"""
        data = {
            "zellij": {
                "tags": ["cat:terminal", "os:linux"]
            },
            "bat": {
                "description": "A cat clone with syntax highlighting",
                "tags": ["cat:cli-tool", "os:macos", "pm:homebrew"]
            }
        }
        
        write_toml(data, self.test_toml_path)
        
        with open(self.test_toml_path, 'r') as f:
            content = f.read()
            
        # Check that packages are in alphabetical order
        bat_pos = content.find('[bat]')
        zellij_pos = content.find('[zellij]')
        self.assertLess(bat_pos, zellij_pos, "Packages should be alphabetically ordered")
        
        # Check that description is only in bat
        self.assertIn('description = "A cat clone with syntax highlighting"', content)

    def test_write_toml_special_characters_in_package_names(self):
        """Test handling of special characters in package names"""
        data = {
            "python@3.11": {
                "description": "Python 3.11",
                "tags": ["cat:programming"]
            },
            "test.package": {
                "tags": ["cat:utility"]
            }
        }
        
        write_toml(data, self.test_toml_path)
        
        with open(self.test_toml_path, 'r') as f:
            content = f.read()
            
        # Check that special characters are properly quoted
        self.assertIn('["python@3.11"]', content)
        self.assertIn('["test.package"]', content)

    def test_roundtrip_formatting_consistency(self):
        """Test that formatting is consistent across read/write cycles"""
        original_data = {
            "test-package": {
                "description": "Test description",
                "tags": ["z-tag", "a-tag", "m-tag"]
            }
        }
        
        # Write the data
        write_toml(original_data, self.test_toml_path)
        
        # Read it back
        with open(self.test_toml_path, 'r') as f:
            loaded_data = toml.load(f)
            
        # Check that tags are sorted alphabetically (our formatter sorts them)
        self.assertEqual(loaded_data["test-package"]["tags"], ["a-tag", "m-tag", "z-tag"])
        
        # Write it again
        second_toml_path = os.path.join(self.temp_dir, "second.toml")
        write_toml(loaded_data, second_toml_path)
        
        # Read both files and compare
        with open(self.test_toml_path, 'r') as f:
            first_content = f.read()
        with open(second_toml_path, 'r') as f:
            second_content = f.read()
            
        # Content should be identical after roundtrip
        self.assertEqual(first_content, second_content)

    def test_reformat_script_functionality(self):
        """Test that the reformat script works correctly"""
        # Create a test TOML with unordered tags
        test_data = {
            "test-pkg": {
                "description": "Test package",
                "tags": ["z-last", "a-first", "m-middle"]
            }
        }
        
        # Write using standard toml library (not our formatter)
        with open(self.test_toml_path, 'w') as f:
            toml.dump(test_data, f)
            
        # Save original path and change working directory
        original_cwd = os.getcwd()
        try:
            os.chdir(self.temp_dir)
            
            # Create a package_mappings.toml file for the reformat script
            package_mappings_path = os.path.join(self.temp_dir, "packages", "package_mappings.toml")
            os.makedirs(os.path.dirname(package_mappings_path), exist_ok=True)
            
            with open(package_mappings_path, 'w') as f:
                toml.dump(test_data, f)
            
            # Run the reformat script
            import sys
            from unittest.mock import patch
            
            with patch.object(sys, 'argv', ['reformat_toml_tags.py']):
                try:
                    reformat_main()
                except SystemExit:
                    pass  # Script calls sys.exit normally
                    
            # Check that the file was reformatted
            with open(package_mappings_path, 'r') as f:
                reformatted_content = f.read()
                
            # Should have proper tag formatting
            self.assertIn('tags = [', reformatted_content)
            self.assertIn('    "a-first",', reformatted_content)
            self.assertIn('    "m-middle",', reformatted_content)
            self.assertIn('    "z-last"', reformatted_content)
            
        finally:
            os.chdir(original_cwd)


class TestTagFormattingEdgeCases(unittest.TestCase):
    """Test edge cases in tag formatting"""

    def test_format_tags_with_duplicates(self):
        """Test that duplicate tags are handled correctly"""
        tags = ["cat:utility", "cat:utility", "os:linux"]
        result = format_tags(tags)
        # Should only include unique tags
        self.assertEqual(result.count('"cat:utility"'), 1)

    def test_format_tags_with_namespaces(self):
        """Test that namespace ordering works correctly"""
        tags = ["role:development", "cat:cli-tool", "os:linux", "pm:homebrew"]
        result = format_tags(tags)
        
        # Should be alphabetically ordered
        lines = result.split('\n')
        tag_lines = [line.strip().rstrip(',') for line in lines if line.strip().startswith('"')]
        
        expected_order = ['"cat:cli-tool"', '"os:linux"', '"pm:homebrew"', '"role:development"']
        self.assertEqual(tag_lines, expected_order)

    def test_format_tags_with_special_characters(self):
        """Test tags with special characters"""
        tags = ["pm:homebrew:darwin", "cat:cli-tool", "arch:x86_64"]
        result = format_tags(tags)
        
        # Should handle colons and underscores correctly
        self.assertIn('"pm:homebrew:darwin"', result)
        self.assertIn('"arch:x86_64"', result)


if __name__ == "__main__":
    # Set up test environment
    os.chdir(Path(__file__).parent.parent)
    
    # Run the tests
    unittest.main(verbosity=2)