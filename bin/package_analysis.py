#!/usr/bin/env python3
"""
Clean package analysis tool for generating complete package mappings.

This tool treats Repology as the authoritative source and can:
1. Generate complete TOML mappings from package lists
2. Process specific packages for debugging
3. Validate roundtrip generation (TOML → package files → TOML)
4. Support custom package list files

Architecture: Repology-first → fallback to individual package managers → clean TOML generation
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Set, Optional, Any, Tuple

# Try to import dependencies
try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

try:
    import tomllib  # Python 3.11+
    def load_toml(filepath):
        with open(filepath, 'rb') as f:
            return tomllib.load(f)
except ImportError:
    try:
        import toml
        def load_toml(filepath):
            with open(filepath, 'r') as f:
                return toml.load(f)
    except ImportError:
        def load_toml(filepath):
            raise ImportError("No TOML library available. Install with: pip install toml")

def write_toml(data: Dict[str, Any], filepath: str) -> None:
    """Write data to TOML file with proper formatting."""
    with open(filepath, 'w') as f:
        for section_name, section_data in sorted(data.items()):
            f.write(f"[{section_name}]\n")
            for key, value in sorted(section_data.items()):
                if isinstance(value, bool):
                    f.write(f"{key} = {str(value).lower()}\n")
                elif isinstance(value, str):
                    f.write(f"{key} = \"{value}\"\n")
                else:
                    f.write(f"{key} = {value}\n")
            f.write("\n")


class PackageListParser:
    """Parse different package list file formats."""
    
    @staticmethod
    def parse_brewfile(filepath: str) -> Set[str]:
        """Parse Brewfile and extract package names."""
        packages = set()
        if not os.path.exists(filepath):
            return packages
            
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line.startswith('brew '):
                    # Extract package name from brew "package-name"
                    match = re.search(r'brew\s+"([^"]+)"', line)
                    if match:
                        package = match.group(1)
                        # Remove tap prefix if present
                        if '/' in package:
                            package = package.split('/')[-1]
                        packages.add(package)
        return packages
    
    @staticmethod
    def parse_simple_list(filepath: str) -> Set[str]:
        """Parse simple package list (one package per line)."""
        packages = set()
        if not os.path.exists(filepath):
            return packages
            
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    packages.add(line)
        return packages
    
    @classmethod
    def parse_file(cls, filepath: str) -> Set[str]:
        """Auto-detect file format and parse accordingly."""
        filename = os.path.basename(filepath).lower()
        
        if 'brewfile' in filename:
            return cls.parse_brewfile(filepath)
        else:
            return cls.parse_simple_list(filepath)


class RepologyClient:
    """Client for querying Repology API with caching and rate limiting."""
    
    def __init__(self, cache_file: str = "repology_cache.json"):
        self.cache_file = cache_file
        self.cache = self._load_cache()
        self.rate_limit_delay = 0.6  # ~100 requests/minute
        
    def _load_cache(self) -> Dict[str, Any]:
        """Load cache from file."""
        if os.path.exists(self.cache_file):
            try:
                with open(self.cache_file, 'r') as f:
                    return json.load(f)
            except:
                return {}
        return {}
    
    def _save_cache(self) -> None:
        """Save cache to file."""
        try:
            with open(self.cache_file, 'w') as f:
                json.dump(self.cache, f, indent=2)
        except:
            pass  # Cache save failed, continue anyway
    
    def query_package(self, package_name: str) -> Optional[Dict[str, Any]]:
        """Query Repology for package information."""
        if not REQUESTS_AVAILABLE:
            print(f"    Warning: requests library not available, skipping Repology query for {package_name}")
            return None
            
        # Check cache first
        if package_name in self.cache:
            return self.cache[package_name]
        
        print(f"    Querying Repology for {package_name}...")
        
        try:
            url = f"https://repology.org/api/v1/project/{package_name}"
            response = requests.get(url, timeout=15)
            time.sleep(self.rate_limit_delay)
            
            if response.status_code == 200:
                data = response.json()
                result = self._parse_repology_response(data)
            elif response.status_code == 404:
                result = None  # Package not found
            else:
                print(f"    Warning: Repology API error {response.status_code} for {package_name}")
                return None
            
            # Update cache
            self.cache[package_name] = result
            self._save_cache()
            return result
            
        except Exception as e:
            print(f"    Warning: Repology query failed for {package_name}: {e}")
            return None
    
    def _parse_repology_response(self, data: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Parse Repology API response."""
        platforms = {
            'arch_official': False, 'arch_aur': False,
            'debian': False, 'ubuntu': False, 'fedora': False,
            'homebrew': False, 'flatpak': False
        }
        
        package_names = {
            'arch': None, 'apt': None, 'fedora': None, 'flatpak': None
        }
        
        description = None
        description_priority = 0
        
        for entry in data:
            repo = entry.get('repo', '').lower()
            srcname = entry.get('srcname', '')
            binname = entry.get('binname', srcname)
            entry_desc = entry.get('summary') or entry.get('description', '')
            
            # Description priority (higher = better)
            current_priority = 0
            if 'homebrew' in repo or 'brew' in repo:
                current_priority = 5
            elif 'debian' in repo or 'ubuntu' in repo:
                current_priority = 4
            elif 'fedora' in repo:
                current_priority = 3
            elif 'arch' in repo and 'aur' not in repo:
                current_priority = 2
            elif 'aur' in repo:
                current_priority = 1
            
            if entry_desc and current_priority > description_priority:
                description = entry_desc.strip()
                description_priority = current_priority
            
            # Track platform availability and package names
            if 'arch' in repo and 'aur' not in repo:
                platforms['arch_official'] = True
                if not package_names['arch']:
                    package_names['arch'] = binname or srcname
            elif 'aur' in repo:
                platforms['arch_aur'] = True
                if not package_names['arch']:
                    package_names['arch'] = binname or srcname
            elif 'debian' in repo:
                platforms['debian'] = True
                if not package_names['apt']:
                    package_names['apt'] = binname or srcname
            elif 'ubuntu' in repo:
                platforms['ubuntu'] = True
                if not package_names['apt'] and not platforms['debian']:
                    package_names['apt'] = binname or srcname
            elif 'fedora' in repo:
                platforms['fedora'] = True
                if not package_names['fedora']:
                    package_names['fedora'] = binname or srcname
            elif 'homebrew' in repo or 'brew' in repo:
                platforms['homebrew'] = True
            elif 'flatpak' in repo or 'flathub' in repo:
                platforms['flatpak'] = True
                if not package_names['flatpak']:
                    package_names['flatpak'] = binname or srcname
        
        return {
            'platforms': platforms,
            'package_names': package_names,
            'description': description
        }


class BrewClient:
    """Client for querying Homebrew."""
    
    @staticmethod
    def query_package(package_name: str) -> Optional[Dict[str, Any]]:
        """Query Homebrew for package information."""
        try:
            result = subprocess.run(
                ['brew', 'info', '--json', package_name],
                capture_output=True, text=True, timeout=10
            )
            
            if result.returncode != 0:
                return None
            
            data = json.loads(result.stdout)
            if not data:
                return None
            
            package_info = data[0]
            
            # Check if it's a cask
            tap = package_info.get('tap', '')
            is_cask = '/cask' in tap or tap == 'homebrew/cask'
            
            # Check platform support from bottle files
            bottle_files = package_info.get('bottle', {}).get('stable', {}).get('files', {})
            
            supports_darwin = any(
                platform for platform in bottle_files.keys() 
                if any(mac_arch in platform for mac_arch in ['arm64_', 'sonoma', 'ventura', 'monterey'])
            )
            
            supports_linux = any(
                platform for platform in bottle_files.keys()
                if 'linux' in platform
            )
            
            return {
                'supports_darwin': supports_darwin,
                'supports_linux': supports_linux,
                'is_cask': is_cask
            }
            
        except Exception as e:
            print(f"    Warning: Homebrew query failed for {package_name}: {e}")
            return None


def collect_packages_from_lists(package_lists: List[str]) -> Set[str]:
    """Collect all packages from the specified package list files."""
    all_packages = set()
    
    for package_list in package_lists:
        if not os.path.exists(package_list):
            print(f"Warning: Package list file not found: {package_list}")
            continue
            
        packages = PackageListParser.parse_file(package_list)
        print(f"Found {len(packages)} packages in {package_list}")
        all_packages.update(packages)
    
    return all_packages


def generate_package_entry(package_name: str, repology_client: RepologyClient, 
                         existing_toml: Dict[str, Any]) -> Dict[str, Any]:
    """Generate a complete TOML entry for a single package."""
    
    # Start with base structure
    entry = {
        'arch-pkg': '',
        'apt-pkg': '',
        'fedora-pkg': '',
        'flatpak-pkg': '',
        'priority': 'medium',
        'description': f'TODO: Add description for {package_name}'
    }
    
    # Try Repology first (authoritative source)
    repology_data = repology_client.query_package(package_name)
    
    if repology_data:
        platforms = repology_data['platforms']
        pkg_names = repology_data['package_names']
        
        # Use Repology description if available
        if repology_data['description']:
            entry['description'] = repology_data['description']
        
        # Fill in package names
        if pkg_names['arch']:
            entry['arch-pkg'] = pkg_names['arch']
            entry['arch-is-aur'] = platforms['arch_aur']
        
        if pkg_names['apt']:
            entry['apt-pkg'] = pkg_names['apt']
        
        if pkg_names['fedora']:
            entry['fedora-pkg'] = pkg_names['fedora']
        
        if pkg_names['flatpak']:
            entry['flatpak-pkg'] = pkg_names['flatpak']
        
        # Add Homebrew fields if it exists there
        if platforms['homebrew']:
            brew_data = BrewClient.query_package(package_name)
            if brew_data:
                entry.update({
                    'brew-supports-linux': brew_data['supports_linux'],
                    'brew-supports-darwin': brew_data['supports_darwin'],
                    'brew-is-cask': brew_data['is_cask']
                })
            else:
                # Fallback defaults
                entry.update({
                    'brew-supports-linux': False,
                    'brew-supports-darwin': True,
                    'brew-is-cask': False
                })
    else:
        # Fallback: query Homebrew directly
        print(f"    No Repology data, trying Homebrew...")
        brew_data = BrewClient.query_package(package_name)
        if brew_data:
            entry.update({
                'brew-supports-linux': brew_data['supports_linux'],
                'brew-supports-darwin': brew_data['supports_darwin'],
                'brew-is-cask': brew_data['is_cask']
            })
    
    # Merge with existing entry if available (preserve manual edits)
    if package_name in existing_toml:
        existing_entry = existing_toml[package_name]
        # Preserve manually edited descriptions and other manual fields
        if existing_entry.get('description') and 'TODO' not in existing_entry['description']:
            entry['description'] = existing_entry['description']
        # Preserve manual priority settings
        if existing_entry.get('priority'):
            entry['priority'] = existing_entry['priority']
    
    return entry


def generate_complete_toml(package_lists: List[str], specific_packages: List[str] = None,
                          existing_toml_path: str = None, repology_cache: str = "repology_cache.json") -> Dict[str, Any]:
    """Generate complete TOML mappings from scratch."""
    
    # Load existing TOML for reference
    existing_toml = {}
    if existing_toml_path and os.path.exists(existing_toml_path):
        existing_toml = load_toml(existing_toml_path)
        print(f"Loaded {len(existing_toml)} existing entries from {existing_toml_path}")
    
    # Collect packages to process
    if specific_packages:
        all_packages = set(specific_packages)
        print(f"Processing {len(all_packages)} specific packages")
    else:
        all_packages = collect_packages_from_lists(package_lists)
        # Add any packages from existing TOML that might not be in lists
        all_packages.update(existing_toml.keys())
        print(f"Processing {len(all_packages)} total packages")
    
    # Initialize clients
    repology_client = RepologyClient(repology_cache)
    
    # Generate entries
    complete_toml = {}
    
    for i, package_name in enumerate(sorted(all_packages), 1):
        print(f"[{i}/{len(all_packages)}] Processing {package_name}")
        
        entry = generate_package_entry(package_name, repology_client, existing_toml)
        complete_toml[package_name] = entry
    
    return complete_toml


def validate_roundtrip(toml_path: str, package_lists: List[str]) -> bool:
    """Validate roundtrip: package files → TOML → package files."""
    
    print("=== Roundtrip Validation ===")
    
    # Step 1: Generate TOML from original package files
    print("Step 1: Generating TOML from package files...")
    original_toml = generate_complete_toml(
        package_lists=package_lists,
        existing_toml_path=toml_path,
        repology_cache="validation_cache.json"
    )
    
    # Step 2: Generate package files from TOML
    print("Step 2: Generating package files from TOML...")
    
    # We need to import the generator functions
    sys.path.append(str(Path(__file__).parent))
    try:
        from package_generators import generate_package_files, PlatformDetector, PackageFilter
        
        # Create temporary TOML file
        temp_toml = "temp_validation.toml"
        write_toml(original_toml, temp_toml)
        
        try:
            generated_files = generate_package_files(
                toml_path=temp_toml,
                output_dir=None  # Don't write files, just get content
            )
            
            # Step 3: Parse generated files back to package sets
            print("Step 3: Parsing generated files...")
            generated_packages = {}
            
            for filename, content in generated_files.items():
                if filename == 'Brewfile':
                    # Parse Brewfile content
                    packages = set()
                    for line in content.split('\n'):
                        line = line.strip()
                        if line.startswith('brew ') or line.startswith('cask '):
                            import re
                            match = re.search(r'(?:brew|cask)\s+"([^"]+)"', line)
                            if match:
                                package = match.group(1)
                                if '/' in package:
                                    package = package.split('/')[-1]
                                packages.add(package)
                    generated_packages['brewfile'] = packages
                else:
                    # Parse simple list files
                    packages = set()
                    for line in content.split('\n'):
                        line = line.strip()
                        if line and not line.startswith('#'):
                            # Remove AUR comments
                            if '  # AUR' in line:
                                line = line.replace('  # AUR', '')
                            packages.add(line.strip())
                    generated_packages[filename.lower()] = packages
            
            # Step 4: Compare original vs generated
            print("Step 4: Comparing original vs generated...")
            
            # Load original package files
            original_packages = {}
            for package_list in package_lists:
                if os.path.exists(package_list):
                    packages = PackageListParser.parse_file(package_list)
                    filename = os.path.basename(package_list).lower()
                    original_packages[filename] = packages
            
            # Compare results
            validation_passed = True
            
            for filename, original_set in original_packages.items():
                generated_set = generated_packages.get(filename, set())
                
                missing_in_generated = original_set - generated_set
                extra_in_generated = generated_set - original_set
                
                print(f"\n{filename}:")
                print(f"  Original: {len(original_set)} packages")
                print(f"  Generated: {len(generated_set)} packages")
                
                if missing_in_generated:
                    print(f"  Missing in generated: {sorted(missing_in_generated)}")
                    validation_passed = False
                
                if extra_in_generated:
                    print(f"  Extra in generated: {sorted(extra_in_generated)}")
                    # Extra packages might be OK (filtering can add packages)
                
                if not missing_in_generated and not extra_in_generated:
                    print(f"  ✓ Perfect match")
            
            print(f"\nValidation result: {'PASSED' if validation_passed else 'FAILED'}")
            return validation_passed
            
        finally:
            # Cleanup
            if os.path.exists(temp_toml):
                os.remove(temp_toml)
            if os.path.exists("validation_cache.json"):
                os.remove("validation_cache.json")
        
    except ImportError as e:
        print(f"Error: Cannot import package_generators: {e}")
        return False


def main():
    parser = argparse.ArgumentParser(description='Generate complete package mappings from package lists')
    
    # Input options
    parser.add_argument('--package-lists', nargs='+', 
                       help='Package list files to process (default: common files)')
    parser.add_argument('--package', nargs='+', dest='specific_packages',
                       help='Process specific packages only (for debugging)')
    parser.add_argument('--existing-toml', 
                       help='Path to existing TOML file for reference')
    
    # Output options
    parser.add_argument('--output', '-o',
                       help='Write complete TOML to file')
    parser.add_argument('--cache', default='repology_cache.json',
                       help='Repology cache file (default: repology_cache.json)')
    
    # Validation mode
    parser.add_argument('--validate', action='store_true',
                       help='Validate roundtrip generation')
    
    args = parser.parse_args()
    
    # Get script directory for default paths
    script_dir = Path(__file__).parent
    dotfiles_dir = script_dir.parent
    
    # Set default package lists if none provided
    if not args.package_lists and not args.specific_packages:
        default_lists = [
            dotfiles_dir / "Brewfile.in",
            dotfiles_dir / "Archfile", 
            dotfiles_dir / "Aptfile",
            dotfiles_dir / "Flatfile"
        ]
        args.package_lists = [str(f) for f in default_lists if f.exists()]
    
    # Set default existing TOML if none provided
    if not args.existing_toml:
        default_toml = dotfiles_dir / "package_mappings.toml"
        if default_toml.exists():
            args.existing_toml = str(default_toml)
    
    # Handle validation mode
    if args.validate:
        if not args.package_lists:
            print("Error: --validate requires --package-lists to be specified")
            sys.exit(1)
        
        validation_passed = validate_roundtrip(
            toml_path=args.existing_toml,
            package_lists=args.package_lists
        )
        sys.exit(0 if validation_passed else 1)
    
    print("=== Package Analysis Tool ===")
    print(f"Package lists: {args.package_lists or 'None'}")
    print(f"Specific packages: {args.specific_packages or 'None'}")
    print(f"Existing TOML: {args.existing_toml or 'None'}")
    print()
    
    # Generate complete TOML
    complete_toml = generate_complete_toml(
        package_lists=args.package_lists or [],
        specific_packages=args.specific_packages,
        existing_toml_path=args.existing_toml,
        repology_cache=args.cache
    )
    
    # Output results
    if args.output:
        write_toml(complete_toml, args.output)
        print(f"\nComplete TOML written to: {args.output}")
    else:
        print(f"\nGenerated {len(complete_toml)} TOML entries:")
        print("=" * 50)
        for package_name, entry in sorted(complete_toml.items()):
            print(f"\n[{package_name}]")
            for key, value in entry.items():
                if value or value is False:
                    if isinstance(value, bool):
                        print(f"{key} = {str(value).lower()}")
                    else:
                        print(f"{key} = \"{value}\"")
    
    print(f"\nSUMMARY: Generated {len(complete_toml)} complete package entries")


if __name__ == "__main__":
    sys.exit(main())