#!/usr/bin/env python3
"""
Homebrew Client for package description extraction

This module provides a client to query Homebrew for package information,
specifically descriptions, using 'brew info' commands.
"""

import json
import subprocess
import sys
from pathlib import Path
from typing import Dict, Optional, Any


class HomebrewClient:
    """Client for querying Homebrew package information."""
    
    def __init__(self, timeout: int = 30):
        """
        Initialize the Homebrew client.
        
        Args:
            timeout: Timeout in seconds for brew commands
        """
        self.timeout = timeout
        self._available = None
    
    def is_available(self) -> bool:
        """Check if Homebrew is available on the system."""
        if self._available is not None:
            return self._available
            
        try:
            result = subprocess.run(
                ['brew', '--version'],
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            self._available = result.returncode == 0
        except (subprocess.TimeoutExpired, FileNotFoundError):
            self._available = False
            
        return self._available
    
    def get_package_info(self, package_name: str) -> Optional[Dict[str, Any]]:
        """
        Get package information from Homebrew.
        
        Args:
            package_name: Name of the package to query
            
        Returns:
            Dictionary with package info or None if not found/error
        """
        if not self.is_available():
            return None
            
        try:
            # Try formula first, then cask if that fails
            info = self._get_formula_info(package_name)
            if info is None:
                info = self._get_cask_info(package_name)
            return info
        except Exception as e:
            print(f"Warning: Failed to get Homebrew info for {package_name}: {e}")
            return None
    
    def get_package_description(self, package_name: str) -> Optional[str]:
        """
        Get package description from Homebrew.
        
        Args:
            package_name: Name of the package to query
            
        Returns:
            Package description string or None if not found
        """
        info = self.get_package_info(package_name)
        if info:
            return info.get('desc', '').strip()
        return None
    
    def _get_formula_info(self, package_name: str) -> Optional[Dict[str, Any]]:
        """Get formula information using 'brew info --json'."""
        try:
            result = subprocess.run(
                ['brew', 'info', '--json=v2', package_name],
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            
            if result.returncode != 0:
                return None
                
            data = json.loads(result.stdout)
            formulae = data.get('formulae', [])
            
            if formulae:
                formula = formulae[0]
                return {
                    'name': formula.get('name'),
                    'desc': formula.get('desc', ''),
                    'homepage': formula.get('homepage'),
                    'versions': formula.get('versions', {}),
                    'type': 'formula'
                }
                
        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError) as e:
            print(f"Warning: Failed to parse formula info for {package_name}: {e}")
            
        return None
    
    def _get_cask_info(self, package_name: str) -> Optional[Dict[str, Any]]:
        """Get cask information using 'brew info --json' for casks."""
        try:
            result = subprocess.run(
                ['brew', 'info', '--json=v2', '--cask', package_name],
                capture_output=True,
                text=True,
                timeout=self.timeout
            )
            
            if result.returncode != 0:
                return None
                
            data = json.loads(result.stdout)
            casks = data.get('casks', [])
            
            if casks:
                cask = casks[0]
                return {
                    'name': cask.get('token'),
                    'desc': cask.get('desc', ''),
                    'homepage': cask.get('homepage'),
                    'version': cask.get('version'),
                    'type': 'cask'
                }
                
        except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError) as e:
            print(f"Warning: Failed to parse cask info for {package_name}: {e}")
            
        return None
    
    def batch_get_descriptions(self, package_names: list) -> Dict[str, str]:
        """
        Get descriptions for multiple packages.
        
        Args:
            package_names: List of package names to query
            
        Returns:
            Dictionary mapping package names to descriptions
        """
        descriptions = {}
        
        for package_name in package_names:
            desc = self.get_package_description(package_name)
            if desc:
                descriptions[package_name] = desc
                
        return descriptions


# Example usage
if __name__ == "__main__":
    client = HomebrewClient()
    
    if len(sys.argv) > 1:
        package_name = sys.argv[1]
        info = client.get_package_info(package_name)
        if info:
            print(f"Package: {info['name']}")
            print(f"Description: {info['desc']}")
            print(f"Type: {info['type']}")
            if 'homepage' in info:
                print(f"Homepage: {info['homepage']}")
        else:
            print(f"Package '{package_name}' not found in Homebrew")
    else:
        # Test with a few common packages
        test_packages = ['git', 'vim', 'python@3.11', 'firefox']
        descriptions = client.batch_get_descriptions(test_packages)
        
        print("Homebrew package descriptions:")
        for pkg, desc in descriptions.items():
            print(f"  {pkg}: {desc}")