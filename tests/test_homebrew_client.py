#!/usr/bin/env python3
"""
Tests for Homebrew client functionality

Tests cover:
- HomebrewClient availability detection
- Package description extraction
- Formula vs cask handling  
- Fallback behavior when Repology fails
- Integration with package analysis
- Error handling and edge cases
"""

import os
import sys
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch, MagicMock

# Add the bin directory to the path
sys.path.insert(0, str(Path(__file__).parent.parent / "bin"))

try:
    from homebrew_client import HomebrewClient
    from package_analysis_tagged import enhance_package_entry_with_tags
except ImportError as e:
    print(f"Error importing modules: {e}")
    sys.exit(1)


class TestHomebrewClient(unittest.TestCase):
    """Test HomebrewClient functionality"""

    def setUp(self):
        self.client = HomebrewClient(timeout=10)

    def test_homebrew_availability_detection(self):
        """Test that Homebrew availability is correctly detected"""
        # Test with mocked subprocess
        with patch('subprocess.run') as mock_run:
            # Test when Homebrew is available
            mock_run.return_value.returncode = 0
            client = HomebrewClient()
            self.assertTrue(client.is_available())
            
            # Test when Homebrew is not available
            mock_run.return_value.returncode = 1
            client = HomebrewClient()
            self.assertFalse(client.is_available())
            
            # Test when brew command doesn't exist
            mock_run.side_effect = FileNotFoundError()
            client = HomebrewClient()
            self.assertFalse(client.is_available())

    def test_get_package_description_formula(self):
        """Test getting description for a Homebrew formula"""
        mock_formula_json = '''
        {
            "formulae": [{
                "name": "git",
                "desc": "Distributed revision control system",
                "homepage": "https://git-scm.com",
                "versions": {"stable": "2.42.0"}
            }],
            "casks": []
        }
        '''
        
        with patch('subprocess.run') as mock_run:
            # Mock successful formula lookup
            mock_run.side_effect = [
                # brew --version (availability check)
                Mock(returncode=0),
                # brew info --json=v2 git (formula lookup)
                Mock(returncode=0, stdout=mock_formula_json)
            ]
            
            client = HomebrewClient()
            desc = client.get_package_description('git')
            self.assertEqual(desc, "Distributed revision control system")

    def test_get_package_description_cask(self):
        """Test getting description for a Homebrew cask"""
        mock_cask_json = '''
        {
            "formulae": [],
            "casks": [{
                "token": "firefox",
                "desc": "Web browser",
                "homepage": "https://www.mozilla.org/firefox/",
                "version": "118.0.2"
            }]
        }
        '''
        
        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = [
                # brew --version (availability check)
                Mock(returncode=0),
                # brew info --json=v2 firefox (formula lookup fails)
                Mock(returncode=1),
                # brew info --json=v2 --cask firefox (cask lookup succeeds)
                Mock(returncode=0, stdout=mock_cask_json)
            ]
            
            client = HomebrewClient()
            desc = client.get_package_description('firefox')
            self.assertEqual(desc, "Web browser")

    def test_get_package_info_formula(self):
        """Test getting full package info for formula"""
        mock_formula_json = '''
        {
            "formulae": [{
                "name": "python@3.11",
                "desc": "Interpreted, interactive, object-oriented programming language",
                "homepage": "https://www.python.org/",
                "versions": {"stable": "3.11.6"}
            }],
            "casks": []
        }
        '''
        
        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = [
                Mock(returncode=0),  # availability check
                Mock(returncode=0, stdout=mock_formula_json)  # formula lookup
            ]
            
            client = HomebrewClient()
            info = client.get_package_info('python@3.11')
            
            self.assertIsNotNone(info)
            self.assertEqual(info['name'], 'python@3.11')
            self.assertEqual(info['desc'], 'Interpreted, interactive, object-oriented programming language')
            self.assertEqual(info['type'], 'formula')
            self.assertEqual(info['homepage'], 'https://www.python.org/')

    def test_get_package_info_cask(self):
        """Test getting full package info for cask"""
        mock_cask_json = '''
        {
            "formulae": [],
            "casks": [{
                "token": "visual-studio-code",
                "desc": "Open-source code editor",
                "homepage": "https://code.visualstudio.com/",
                "version": "1.84.0"
            }]
        }
        '''
        
        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = [
                Mock(returncode=0),  # availability check
                Mock(returncode=1),  # formula lookup fails
                Mock(returncode=0, stdout=mock_cask_json)  # cask lookup succeeds
            ]
            
            client = HomebrewClient()
            info = client.get_package_info('visual-studio-code')
            
            self.assertIsNotNone(info)
            self.assertEqual(info['name'], 'visual-studio-code')
            self.assertEqual(info['desc'], 'Open-source code editor')
            self.assertEqual(info['type'], 'cask')

    def test_package_not_found(self):
        """Test behavior when package is not found"""
        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = [
                Mock(returncode=0),  # availability check
                Mock(returncode=1),  # formula lookup fails
                Mock(returncode=1)   # cask lookup fails
            ]
            
            client = HomebrewClient()
            desc = client.get_package_description('nonexistent-package')
            self.assertIsNone(desc)
            
            info = client.get_package_info('nonexistent-package')
            self.assertIsNone(info)

    def test_json_parsing_error(self):
        """Test handling of JSON parsing errors"""
        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = [
                Mock(returncode=0),  # availability check
                Mock(returncode=0, stdout='invalid json')  # invalid JSON response
            ]
            
            client = HomebrewClient()
            with patch('builtins.print'):  # Suppress warning output
                desc = client.get_package_description('test-package')
            self.assertIsNone(desc)

    def test_subprocess_timeout(self):
        """Test handling of subprocess timeouts"""
        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = [
                Mock(returncode=0),  # availability check
                subprocess.TimeoutExpired('brew', 10)  # timeout on info command
            ]
            
            client = HomebrewClient()
            with patch('builtins.print'):  # Suppress warning output
                desc = client.get_package_description('test-package')
            self.assertIsNone(desc)

    def test_batch_get_descriptions(self):
        """Test batch description retrieval"""
        mock_responses = {
            'git': 'Distributed revision control system',
            'vim': 'Vi Improved text editor',
            'python@3.11': 'Python programming language'
        }
        
        with patch.object(HomebrewClient, 'get_package_description') as mock_get_desc:
            mock_get_desc.side_effect = lambda pkg: mock_responses.get(pkg)
            
            client = HomebrewClient()
            descriptions = client.batch_get_descriptions(['git', 'vim', 'python@3.11', 'nonexistent'])
            
            expected = {
                'git': 'Distributed revision control system',
                'vim': 'Vi Improved text editor', 
                'python@3.11': 'Python programming language'
            }
            self.assertEqual(descriptions, expected)

    def test_empty_description_handling(self):
        """Test handling of empty descriptions"""
        mock_formula_json = '''
        {
            "formulae": [{
                "name": "test-package",
                "desc": "",
                "homepage": "https://example.com"
            }],
            "casks": []
        }
        '''
        
        with patch('subprocess.run') as mock_run:
            mock_run.side_effect = [
                Mock(returncode=0),  # availability check
                Mock(returncode=0, stdout=mock_formula_json)
            ]
            
            client = HomebrewClient()
            desc = client.get_package_description('test-package')
            self.assertEqual(desc, "")  # Should return empty string, not None


class TestHomebrewDescriptionFallback(unittest.TestCase):
    """Test integration of Homebrew fallback with package analysis"""

    def setUp(self):
        self.mock_repology_client = Mock()
        self.mock_homebrew_client = Mock()

    def test_repology_has_description_no_fallback(self):
        """Test that Homebrew is not called when Repology provides description"""
        # Set up repology to return data with description
        self.mock_repology_client.query_package.return_value = {
            'description': 'Description from Repology',
            'platforms': {'homebrew': True}
        }
        
        entry = {'tags': []}
        result = enhance_package_entry_with_tags(
            'test-package', 
            entry, 
            repology_client=self.mock_repology_client,
            homebrew_client=self.mock_homebrew_client
        )
        
        # Should use Repology description
        self.assertEqual(result['description'], 'Description from Repology')
        # Homebrew should not be called
        self.mock_homebrew_client.get_package_description.assert_not_called()

    def test_repology_no_description_homebrew_fallback(self):
        """Test that Homebrew is called when Repology has no description"""
        # Set up repology to return data without description
        self.mock_repology_client.query_package.return_value = {
            'platforms': {'homebrew': True}
        }
        
        # Set up homebrew to return description
        self.mock_homebrew_client.get_package_description.return_value = 'Description from Homebrew'
        self.mock_homebrew_client.get_package_info.return_value = {
            'name': 'test-package',
            'desc': 'Description from Homebrew',
            'type': 'formula',
            'homepage': 'https://example.com'
        }
        
        entry = {'tags': []}
        result = enhance_package_entry_with_tags(
            'test-package',
            entry,
            repology_client=self.mock_repology_client,
            homebrew_client=self.mock_homebrew_client
        )
        
        # Should use Homebrew description
        self.assertEqual(result['description'], 'Description from Homebrew')
        # Homebrew should be called
        self.mock_homebrew_client.get_package_description.assert_called_once_with('test-package')

    def test_repology_empty_description_homebrew_fallback(self):
        """Test that Homebrew is called when Repology has empty description"""
        # Set up repology to return empty description
        self.mock_repology_client.query_package.return_value = {
            'description': '   ',  # whitespace-only description
            'platforms': {'homebrew': True}
        }
        
        self.mock_homebrew_client.get_package_description.return_value = 'Description from Homebrew'
        self.mock_homebrew_client.get_package_info.return_value = {
            'name': 'test-package',
            'desc': 'Description from Homebrew',
            'type': 'formula',
            'homepage': 'https://example.com'
        }
        
        entry = {'tags': []}
        result = enhance_package_entry_with_tags(
            'test-package',
            entry,
            repology_client=self.mock_repology_client,
            homebrew_client=self.mock_homebrew_client
        )
        
        # Should use Homebrew description since Repology had only whitespace
        self.assertEqual(result['description'], 'Description from Homebrew')

    def test_no_repology_homebrew_fallback(self):
        """Test that Homebrew is called when Repology returns nothing"""
        # Set up repology to return None
        self.mock_repology_client.query_package.return_value = None
        
        self.mock_homebrew_client.get_package_description.return_value = 'Description from Homebrew'
        self.mock_homebrew_client.get_package_info.return_value = {
            'name': 'test-package',
            'desc': 'Description from Homebrew',
            'type': 'formula',
            'homepage': 'https://example.com'
        }
        
        entry = {'tags': []}
        result = enhance_package_entry_with_tags(
            'test-package',
            entry,
            repology_client=self.mock_repology_client,
            homebrew_client=self.mock_homebrew_client
        )
        
        # Should use Homebrew description
        self.assertEqual(result['description'], 'Description from Homebrew')

    def test_both_sources_fail(self):
        """Test behavior when both Repology and Homebrew fail"""
        self.mock_repology_client.query_package.return_value = None
        self.mock_homebrew_client.get_package_description.return_value = None
        
        entry = {'tags': []}
        result = enhance_package_entry_with_tags(
            'test-package',
            entry,
            repology_client=self.mock_repology_client,
            homebrew_client=self.mock_homebrew_client
        )
        
        # Should not have a description
        self.assertNotIn('description', result)

    def test_homebrew_exception_handling(self):
        """Test that Homebrew exceptions are handled gracefully"""
        self.mock_repology_client.query_package.return_value = None
        self.mock_homebrew_client.get_package_description.side_effect = Exception("Network error")
        
        entry = {'tags': []}
        with patch('builtins.print'):  # Suppress warning output
            result = enhance_package_entry_with_tags(
                'test-package',
                entry,
                repology_client=self.mock_repology_client,
                homebrew_client=self.mock_homebrew_client
            )
        
        # Should not crash and should not have description
        self.assertNotIn('description', result)

    def test_existing_description_preserved(self):
        """Test that existing descriptions are not overwritten"""
        self.mock_repology_client.query_package.return_value = {
            'description': 'Description from Repology'
        }
        
        entry = {
            'description': 'Existing description',
            'tags': []
        }
        result = enhance_package_entry_with_tags(
            'test-package',
            entry,
            repology_client=self.mock_repology_client,
            homebrew_client=self.mock_homebrew_client
        )
        
        # Should preserve existing description
        self.assertEqual(result['description'], 'Existing description')
        # Neither source should be called
        self.mock_homebrew_client.get_package_description.assert_not_called()

    def test_no_homebrew_client(self):
        """Test behavior when no Homebrew client is provided"""
        self.mock_repology_client.query_package.return_value = None
        
        entry = {'tags': []}
        result = enhance_package_entry_with_tags(
            'test-package',
            entry,
            repology_client=self.mock_repology_client,
            homebrew_client=None
        )
        
        # Should not have description and should not crash
        self.assertNotIn('description', result)

    def test_cache_hit_with_description_extraction(self):
        """Test that descriptions are extracted even with tag cache hits"""
        from package_analysis_cli import analyze_packages, RepologyCache
        from tag_cache_utils import TagCache
        import tempfile
        import json
        
        # Create mock cache data
        mock_repology_cache = {
            'test-package': {
                'description': 'Description from Repology cache',
                'platforms': {'homebrew': True},
                '_timestamp': 1234567890
            }
        }
        
        # Create temporary files
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as cache_file:
            json.dump(mock_repology_cache, cache_file)
            cache_path = cache_file.name
            
        with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as tag_cache_file:
            # Pre-populate tag cache to trigger cache hit
            tag_cache_data = {
                'test-package': {
                    '_timestamp': 1234567890.0,
                    '_repology_timestamp': 1234567890,
                    'tags': ['cat:utility', 'pm:homebrew']
                }
            }
            json.dump(tag_cache_data, tag_cache_file)
            tag_cache_path = tag_cache_file.name
            
        try:
            with tempfile.NamedTemporaryFile(mode='w', suffix='.toml', delete=False) as output_file:
                output_path = output_file.name
                
            # Test that descriptions are extracted even with cache hits
            package_info = {'test-package': {'is_cask': False, 'source_file': 'test'}}
            analyze_packages(
                package_info,
                output_path,
                cache_path,
                tag_cache_file=tag_cache_path,
                use_tag_cache=True
            )
            
            # Read the output and verify description was extracted
            with open(output_path, 'r') as f:
                content = f.read()
                
            self.assertIn('description = "Description from Repology cache"', content)
            
        finally:
            # Clean up temp files
            import os
            for path in [cache_path, tag_cache_path, output_path]:
                try:
                    os.unlink(path)
                except:
                    pass


if __name__ == "__main__":
    # Set up test environment
    os.chdir(Path(__file__).parent.parent)
    
    # Run the tests
    unittest.main(verbosity=2)