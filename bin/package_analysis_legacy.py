#!/usr/bin/env python3
"""
Analyze package files to build a complete package_mappings.toml.

This script treats package_mappings.toml as the single source of truth and:
1. Identifies packages from existing files that need to be added to TOML
2. Detects potential duplicates and suggests consolidations
3. Helps build a complete TOML that can generate all package files
4. Priority: Native packages > Flatpaks > Homebrew
"""

import os
import sys
import json
import subprocess
import time
from pathlib import Path
from collections import defaultdict

try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

# Try to import TOML parser
try:
    import tomllib  # Python 3.11+
    def load_toml(filepath):
        with open(filepath, 'rb') as f:
            return tomllib.load(f)
except ImportError:
    try:
        import toml  # Third-party package
        def load_toml(filepath):
            with open(filepath, 'r') as f:
                return toml.load(f)
    except ImportError:
        # Simple TOML parser for our specific format
        def load_toml(filepath):
            data = {}
            current_section = None
            
            with open(filepath, 'r') as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    # Parse section headers [package_name]
                    if line.startswith('[') and line.endswith(']'):
                        current_section = line[1:-1]
                        data[current_section] = {}
                        continue
                    
                    # Parse key-value pairs
                    if '=' in line and current_section:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip().strip('"')
                        data[current_section][key] = value
            
            return data

def read_package_file(filepath):
    """Read a package file and return a set of package names."""
    if not os.path.exists(filepath):
        return set()
    
    packages = set()
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#'):
                packages.add(line)
    return packages

def read_toml_mappings(toml_path):
    """Read the TOML file and extract all package names and mappings."""
    if not os.path.exists(toml_path):
        print(f"Error: TOML file not found at {toml_path}")
        return {}, {}
    
    data = load_toml(toml_path)
    
    # Extract homebrew package names (section names)
    homebrew_packages = set(data.keys())
    
    # Extract all native package names
    all_native_packages = defaultdict(set)
    for brew_pkg, attrs in data.items():
        if 'arch-pkg' in attrs and attrs['arch-pkg']:
            all_native_packages['arch'].add(attrs['arch-pkg'])
        if 'apt-pkg' in attrs and attrs['apt-pkg']:
            all_native_packages['apt'].add(attrs['apt-pkg'])
        if 'fedora-pkg' in attrs and attrs['fedora-pkg']:
            all_native_packages['fedora'].add(attrs['fedora-pkg'])
        if 'flatpak-pkg' in attrs and attrs['flatpak-pkg']:
            all_native_packages['flatpak'].add(attrs['flatpak-pkg'])
    
    return homebrew_packages, all_native_packages

def find_brewfile_darwin_files(dotfiles_dir):
    """Find all Brewfile-darwin* files."""
    brewfiles = []
    for file in os.listdir(dotfiles_dir):
        if file.startswith('Brewfile-darwin'):
            brewfiles.append(os.path.join(dotfiles_dir, file))
    return brewfiles

def parse_brewfile(filepath):
    """Parse a Brewfile and extract package names."""
    packages = set()
    if not os.path.exists(filepath):
        return packages
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line.startswith('brew '):
                # Extract package name from brew "package-name"
                if '"' in line:
                    start = line.find('"') + 1
                    end = line.find('"', start)
                    if start > 0 and end > start:
                        package = line[start:end]
                        # Remove tap prefix if present
                        if '/' in package:
                            package = package.split('/')[-1]
                        packages.add(package)
    return packages

def normalize_package_name(name):
    """Normalize package names for comparison (remove common prefixes/suffixes)."""
    # Remove common prefixes
    prefixes = ['lib', 'python-', 'python3-', 'node-', 'go-', 'rust-']
    normalized = name.lower()
    
    for prefix in prefixes:
        if normalized.startswith(prefix):
            normalized = normalized[len(prefix):]
            break
    
    # Remove common suffixes
    suffixes = ['-bin', '-git', '-dev', '-devel', '-utils']
    for suffix in suffixes:
        if normalized.endswith(suffix):
            normalized = normalized[:-len(suffix)]
            break
    
    # Handle specific cases
    replacements = {
        'github-cli': 'gh',
        'fd-find': 'fd',
        'du-dust': 'dust',
        'vim-enhanced': 'vim',
        'gnupg2': 'gnupg',
        'shellcheck': 'shellcheck',  # Case normalization
    }
    
    return replacements.get(normalized, normalized)

def find_similar_packages(package_name, existing_packages):
    """Find packages that might be the same as the given package."""
    normalized = normalize_package_name(package_name)
    similar = []
    
    for existing in existing_packages:
        if normalize_package_name(existing) == normalized:
            similar.append(existing)
    
    return similar

def suggest_consolidation(toml_data, new_packages_by_type):
    """Suggest how to consolidate packages into existing TOML entries."""
    suggestions = []
    existing_homebrew = set(toml_data.keys())
    
    # For each new package, see if it can be added to an existing entry
    for pkg_type, packages in new_packages_by_type.items():
        for package in packages:
            similar = find_similar_packages(package, existing_homebrew)
            
            if similar:
                for existing_brew_pkg in similar:
                    # Check if we can add this native package to the existing entry
                    existing_entry = toml_data[existing_brew_pkg]
                    type_key = f"{pkg_type}-pkg"
                    
                    if type_key not in existing_entry or not existing_entry[type_key]:
                        suggestions.append({
                            'action': 'add_to_existing',
                            'existing_homebrew': existing_brew_pkg,
                            'add_field': type_key,
                            'add_value': package,
                            'reason': f'Similar to existing package'
                        })
                    elif existing_entry[type_key] != package:
                        suggestions.append({
                            'action': 'conflict',
                            'existing_homebrew': existing_brew_pkg,
                            'existing_value': existing_entry[type_key],
                            'new_value': package,
                            'field': type_key,
                            'reason': f'Different {pkg_type} package for same tool'
                        })
    
    return suggestions

def get_current_platform():
    """Detect the current platform using the same logic as system_environment.sh."""
    import platform
    
    system = platform.system()
    if system == 'Darwin':
        return {'darwin': True, 'arch_like': False, 'debian_like': False, 'fedora_like': False}
    elif system == 'Linux':
        # Parse /etc/os-release like the shell script does
        try:
            os_release = {}
            with open('/etc/os-release', 'r') as f:
                for line in f:
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        # Remove quotes from value
                        value = value.strip().strip('"').strip("'")
                        os_release[key] = value
            
            id_val = os_release.get('ID', '')
            id_like = os_release.get('ID_LIKE', '')
            
            # Emulate the exact logic from system_environment.sh
            is_arch_like = (id_val == 'arch') or (id_like and id_like == 'arch')
            is_debian_like = (id_val == 'debian') or (id_like and id_like == 'debian')  
            is_fedora_like = (id_val == 'fedora') or (id_like and id_like == 'fedora')
            
            return {
                'darwin': False,
                'arch_like': is_arch_like,
                'debian_like': is_debian_like,
                'fedora_like': is_fedora_like
            }
            
        except FileNotFoundError:
            pass
        
        return {'darwin': False, 'arch_like': False, 'debian_like': False, 'fedora_like': False}
    else:
        return {'darwin': False, 'arch_like': False, 'debian_like': False, 'fedora_like': False}

def check_arch_package(package_name):
    """Check if package exists in Arch repos or AUR."""
    try:
        # Try pacman first (official repos)
        result = subprocess.run(
            ['pacman', '-Si', package_name],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            return True, False  # exists, not AUR
        
        # Try yay for AUR
        result = subprocess.run(
            ['yay', '-Si', package_name],
            capture_output=True,
            text=True,
            timeout=10
        )
        if result.returncode == 0:
            # Check if it's from AUR
            is_aur = 'aur' in result.stdout.lower() or 'Repository     : aur' in result.stdout
            return True, is_aur
        
        return False, False  # doesn't exist
        
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return None, None  # command failed/not available

def check_apt_package(package_name):
    """Check if package exists in apt repositories."""
    try:
        result = subprocess.run(
            ['apt', 'show', package_name],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0
        
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return None  # command failed/not available

def check_fedora_package(package_name):
    """Check if package exists in Fedora repositories."""
    try:
        result = subprocess.run(
            ['dnf', 'info', package_name],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0
        
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return None  # command failed/not available

def query_repology_package(package_name, cache_file="repology_cache.json"):
    """Query Repology API for cross-platform package availability with caching."""
    if not REQUESTS_AVAILABLE:
        return None
    
    # Load cache
    cache = {}
    if os.path.exists(cache_file):
        try:
            with open(cache_file, 'r') as f:
                cache = json.load(f)
        except:
            cache = {}
    
    # Check cache first
    if package_name in cache:
        return cache[package_name]
    
    # Query Repology API
    try:
        url = f"https://repology.org/api/v1/project/{package_name}"
        response = requests.get(url, timeout=15)
        time.sleep(0.6)  # Rate limiting: max ~100 requests/minute
        
        if response.status_code == 200:
            data = response.json()
            result = parse_repology_response(data)
        elif response.status_code == 404:
            result = None  # Package not found
        else:
            return None  # API error
        
        # Update cache
        cache[package_name] = result
        try:
            with open(cache_file, 'w') as f:
                json.dump(cache, f, indent=2)
        except:
            pass  # Cache write failed, continue anyway
        
        return result
        
    except Exception as e:
        print(f"    Warning: Repology query failed for {package_name}: {e}")
        return None

def parse_repology_response(data):
    """Parse Repology API response to extract platform availability, package names, and description."""
    platforms = {
        'arch_official': False,
        'arch_aur': False, 
        'debian': False,
        'ubuntu': False,
        'fedora': False,
        'homebrew': False,
        'flatpak': False
    }
    
    # Track actual package names on each platform
    package_names = {
        'arch': None,
        'apt': None,
        'fedora': None,
        'flatpak': None
    }
    
    # Try to get the best description available
    description = None
    description_priority = 0  # Higher number = better source
    
    for entry in data:
        repo = entry.get('repo', '').lower()
        srcname = entry.get('srcname', '')
        binname = entry.get('binname', srcname)  # Fall back to srcname if no binname
        entry_desc = entry.get('summary') or entry.get('description', '')
        
        # Determine priority of this description source
        current_priority = 0
        if 'homebrew' in repo or 'brew' in repo:
            current_priority = 5  # Homebrew descriptions are usually good
        elif 'debian' in repo or 'ubuntu' in repo:
            current_priority = 4  # Debian descriptions are comprehensive
        elif 'fedora' in repo:
            current_priority = 3  # Fedora descriptions are good
        elif 'arch' in repo and 'aur' not in repo:
            current_priority = 2  # Arch official descriptions
        elif 'aur' in repo:
            current_priority = 1  # AUR descriptions vary in quality
        
        # Use this description if it's better than what we have
        if entry_desc and current_priority > description_priority:
            description = entry_desc.strip()
            description_priority = current_priority
        
        # Track platform availability and package names
        if 'arch' in repo and 'aur' not in repo:
            platforms['arch_official'] = True
            if not package_names['arch']:  # Prefer first official repo package
                package_names['arch'] = binname or srcname
        elif 'aur' in repo:
            platforms['arch_aur'] = True
            if not package_names['arch']:  # Only use AUR if no official package
                package_names['arch'] = binname or srcname
        elif 'debian' in repo:
            platforms['debian'] = True
            if not package_names['apt']:
                package_names['apt'] = binname or srcname
        elif 'ubuntu' in repo:
            platforms['ubuntu'] = True
            if not package_names['apt']:  # Debian takes precedence over Ubuntu
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

def check_flatpak_package(package_id):
    """Check if Flatpak application exists."""
    try:
        result = subprocess.run(
            ['flatpak', 'info', package_id],
            capture_output=True,
            text=True,
            timeout=10
        )
        return result.returncode == 0
        
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return None  # command failed/not available

def get_homebrew_platform_support(package_name):
    """Query Homebrew to determine platform support for a package."""
    try:
        result = subprocess.run(
            ['brew', 'info', '--json', package_name],
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if result.returncode != 0:
            return None, None, False  # Package doesn't exist in Homebrew
        
        data = json.loads(result.stdout)
        if not data:
            return None, None, False
        
        package_info = data[0]
        
        # Check if it's a cask (more robust detection)
        tap = package_info.get('tap', '')
        is_cask = (
            '/cask' in tap or 
            tap == 'homebrew/cask' or
            'cask' in tap.split('/')
        )
        
        # If tap detection is unclear, try direct cask command as fallback
        if not is_cask and not tap:
            try:
                cask_result = subprocess.run(
                    ['brew', 'info', '--cask', package_name],
                    capture_output=True,
                    timeout=5
                )
                is_cask = (cask_result.returncode == 0)
            except:
                pass  # Fallback failed, stick with original detection
        
        # Check bottle files for platform support
        bottle_files = package_info.get('bottle', {}).get('stable', {}).get('files', {})
        
        supports_darwin = any(
            platform for platform in bottle_files.keys() 
            if any(mac_arch in platform for mac_arch in ['arm64_', 'sonoma', 'ventura', 'monterey', 'big_sur'])
        )
        
        supports_linux = any(
            platform for platform in bottle_files.keys()
            if 'linux' in platform
        )
        
        return supports_darwin, supports_linux, is_cask
        
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, json.JSONDecodeError, KeyError):
        # If anything fails, return None to indicate unknown
        return None, None, None

def generate_new_toml_entries(new_packages_by_type, existing_toml, use_repology=False, repology_cache="repology_cache.json"):
    """Generate new TOML entries for packages that don't have existing matches."""
    new_entries = {}
    existing_homebrew = set(existing_toml.keys())
    
    # Process each package type
    all_processed = set()
    
    for pkg_type, packages in new_packages_by_type.items():
        for package in packages:
            if package in all_processed:
                continue
                
            # See if this package has similar packages in other types
            similar_in_other_types = {}
            normalized = normalize_package_name(package)
            
            # Look for the same normalized name in other package types
            for other_type, other_packages in new_packages_by_type.items():
                if other_type != pkg_type:
                    for other_pkg in other_packages:
                        if normalize_package_name(other_pkg) == normalized:
                            similar_in_other_types[other_type] = other_pkg
                            all_processed.add(other_pkg)
            
            # Check if similar already exists in TOML
            existing_similar = find_similar_packages(package, existing_homebrew)
            if existing_similar:
                continue  # Will be handled by consolidation suggestions
            
            # Create new entry with the normalized name as homebrew package
            # Use the shortest/simplest name as the homebrew package name
            all_variants = [package] + list(similar_in_other_types.values())
            homebrew_name = min(all_variants, key=lambda x: (len(x), x))
            
            # If homebrew name is very different from normalized, use normalized
            if normalize_package_name(homebrew_name) != normalized:
                homebrew_name = normalized
            
            
            # Determine which platforms this package is available on
            available_platforms = {pkg_type}
            available_platforms.update(similar_in_other_types.keys())
            
            # Start with all fields as empty strings (deliberately not available)
            new_entry = {
                'arch-pkg': '',
                'apt-pkg': '',
                'fedora-pkg': '',
                'flatpak-pkg': '',
                'priority': 'medium',
                'description': f'TODO: Add description for {homebrew_name}'
            }
            
            # Only add platform-specific fields if the package exists on that platform
            if 'arch' in available_platforms:
                new_entry['arch-is-aur'] = False  # Default, may need manual verification
            
            if 'homebrew' in available_platforms:
                # Query Homebrew for accurate platform support
                print(f"    Querying Homebrew for {homebrew_name}...")
                supports_darwin, supports_linux, is_cask = get_homebrew_platform_support(homebrew_name)
                
                if supports_darwin is not None:
                    # Use actual Homebrew data
                    new_entry.update({
                        'brew-supports-linux': supports_linux,
                        'brew-supports-darwin': supports_darwin,
                        'brew-is-cask': is_cask,
                    })
                else:
                    # Homebrew query failed, use conservative defaults
                    new_entry.update({
                        'brew-supports-linux': False,   # Conservative default
                        'brew-supports-darwin': True,   # Most packages support macOS
                        'brew-is-cask': False,         # Most are formulae, not casks
                    })
                    print(f"    Warning: Could not query Homebrew for {homebrew_name}, using defaults")
                
                # Also query Repology for homebrew packages to find cross-platform availability
                if use_repology:
                    print(f"    Querying Repology for {homebrew_name}...")
                    repology_data = query_repology_package(homebrew_name, repology_cache)
                    if repology_data:
                        pkg_names = repology_data['package_names']
                        platforms = repology_data['platforms']
                        
                        # Update description if we got one from Repology
                        if repology_data['description']:
                            new_entry['description'] = repology_data['description']
                        
                        # Auto-populate cross-platform package names from Repology
                        if pkg_names['arch'] and not new_entry.get('arch-pkg'):
                            new_entry['arch-pkg'] = pkg_names['arch']
                            # Add arch-is-aur field since we found an arch package
                            if platforms['arch_aur']:
                                new_entry['arch-is-aur'] = True
                            elif platforms['arch_official']:
                                new_entry['arch-is-aur'] = False
                            print(f"    Found Arch package: {pkg_names['arch']} (AUR: {platforms['arch_aur']})")
                        
                        if pkg_names['apt'] and not new_entry.get('apt-pkg'):
                            new_entry['apt-pkg'] = pkg_names['apt']
                            print(f"    Found APT package: {pkg_names['apt']}")
                        
                        if pkg_names['fedora'] and not new_entry.get('fedora-pkg'):
                            new_entry['fedora-pkg'] = pkg_names['fedora']
                            print(f"    Found Fedora package: {pkg_names['fedora']}")
                        
                        if pkg_names['flatpak'] and not new_entry.get('flatpak-pkg'):
                            new_entry['flatpak-pkg'] = pkg_names['flatpak']
                            print(f"    Found Flatpak: {pkg_names['flatpak']}")
            
            # Fill in and verify the known packages
            type_mapping = {
                'arch': 'arch-pkg',
                'apt': 'apt-pkg', 
                'fedora': 'fedora-pkg',
                'flatpak': 'flatpak-pkg'
            }
            
            if pkg_type in type_mapping:
                new_entry[type_mapping[pkg_type]] = package
                
                # Verify and get additional metadata for the package
                platform_info = get_current_platform()
                
                # Use Repology if enabled, otherwise fall back to local verification
                if use_repology:
                    print(f"    Querying Repology for {package}...")
                    repology_data = query_repology_package(package, repology_cache)
                    if repology_data:
                        platforms = repology_data['platforms']
                        pkg_names = repology_data['package_names']
                        
                        # Update description if we got one from Repology
                        if repology_data['description']:
                            new_entry['description'] = repology_data['description']
                        
                        # Auto-populate missing platform package names from Repology
                        if pkg_names['arch'] and not new_entry.get('arch-pkg'):
                            new_entry['arch-pkg'] = pkg_names['arch']
                            # Add arch-is-aur field since we found an arch package
                            if platforms['arch_aur']:
                                new_entry['arch-is-aur'] = True
                            elif platforms['arch_official']:
                                new_entry['arch-is-aur'] = False
                            print(f"    Found Arch package: {pkg_names['arch']} (AUR: {platforms['arch_aur']})")
                        
                        if pkg_names['apt'] and not new_entry.get('apt-pkg'):
                            new_entry['apt-pkg'] = pkg_names['apt']
                            print(f"    Found APT package: {pkg_names['apt']}")
                        
                        if pkg_names['fedora'] and not new_entry.get('fedora-pkg'):
                            new_entry['fedora-pkg'] = pkg_names['fedora']
                            print(f"    Found Fedora package: {pkg_names['fedora']}")
                        
                        if pkg_names['flatpak'] and not new_entry.get('flatpak-pkg'):
                            new_entry['flatpak-pkg'] = pkg_names['flatpak']
                            print(f"    Found Flatpak: {pkg_names['flatpak']}")
                elif pkg_type == 'arch' and platform_info['arch_like']:
                    print(f"    Verifying Arch package: {package}")
                    exists, is_aur = check_arch_package(package)
                    if exists is not None:
                        if exists and 'arch-is-aur' in new_entry:
                            new_entry['arch-is-aur'] = is_aur
                        elif not exists:
                            print(f"    Warning: Arch package '{package}' not found in repos")
                    else:
                        print(f"    Warning: Could not verify Arch package '{package}' (pacman/yay not available)")
            
            for other_type, other_pkg in similar_in_other_types.items():
                if other_type in type_mapping:
                    new_entry[type_mapping[other_type]] = other_pkg
                    
                    # Verify the cross-platform package (only on matching platform)
                    if other_type == 'arch' and platform_info['arch_like']:
                        print(f"    Verifying Arch package: {other_pkg}")
                        exists, is_aur = check_arch_package(other_pkg)
                        if exists is not None:
                            if exists and 'arch-is-aur' in new_entry:
                                new_entry['arch-is-aur'] = is_aur
                            elif not exists:
                                print(f"    Warning: Arch package '{other_pkg}' not found in repos")
                    elif other_type == 'apt' and platform_info['debian_like']:
                        print(f"    Verifying APT package: {other_pkg}")
                        exists = check_apt_package(other_pkg)
                        if exists is False:
                            print(f"    Warning: APT package '{other_pkg}' not found in repos")
                        elif exists is None:
                            print(f"    Warning: Could not verify APT package '{other_pkg}' (apt not available)")
                    elif other_type == 'fedora' and platform_info['fedora_like']:
                        print(f"    Verifying Fedora package: {other_pkg}")
                        exists = check_fedora_package(other_pkg)
                        if exists is False:
                            print(f"    Warning: Fedora package '{other_pkg}' not found in repos")
                        elif exists is None:
                            print(f"    Warning: Could not verify Fedora package '{other_pkg}' (dnf not available)")
                    elif other_type == 'flatpak':
                        # Flatpak is only available on Linux platforms
                        if not platform_info['darwin'] and any(platform_info[k] for k in ['arch_like', 'debian_like', 'fedora_like']):
                            print(f"    Verifying Flatpak: {other_pkg}")
                            exists = check_flatpak_package(other_pkg)
                            if exists is False:
                                print(f"    Warning: Flatpak '{other_pkg}' not found")
                            elif exists is None:
                                print(f"    Warning: Could not verify Flatpak '{other_pkg}' (flatpak not available)")
            
            new_entries[homebrew_name] = new_entry
            all_processed.add(package)
    
    return new_entries

def enhance_existing_entries_with_repology(existing_toml, repology_cache):
    """Enhance existing TOML entries with missing platform info from Repology."""
    enhanced_entries = {}
    
    for homebrew_pkg, entry in existing_toml.items():
        # Check if entry is missing platform package names
        missing_platforms = []
        if not entry.get('arch-pkg'):
            missing_platforms.append('arch')
        if not entry.get('apt-pkg'):
            missing_platforms.append('apt')
        if not entry.get('fedora-pkg'):
            missing_platforms.append('fedora')
        if not entry.get('flatpak-pkg'):
            missing_platforms.append('flatpak')
        
        # Skip if entry is already complete
        if not missing_platforms:
            continue
            
        print(f"  Enhancing {homebrew_pkg} (missing: {', '.join(missing_platforms)})")
        
        # Query Repology for this package
        repology_data = query_repology_package(homebrew_pkg, repology_cache)
        if repology_data:
            pkg_names = repology_data['package_names']
            platforms = repology_data['platforms']
            enhanced = False
            
            # Fill in missing platform package names
            if 'arch' in missing_platforms and pkg_names['arch']:
                entry['arch-pkg'] = pkg_names['arch']
                # Add arch-is-aur if not present
                if 'arch-is-aur' not in entry:
                    entry['arch-is-aur'] = platforms['arch_aur']
                print(f"    Added Arch: {pkg_names['arch']} (AUR: {platforms['arch_aur']})")
                enhanced = True
            
            if 'apt' in missing_platforms and pkg_names['apt']:
                entry['apt-pkg'] = pkg_names['apt']
                print(f"    Added APT: {pkg_names['apt']}")
                enhanced = True
            
            if 'fedora' in missing_platforms and pkg_names['fedora']:
                entry['fedora-pkg'] = pkg_names['fedora']
                print(f"    Added Fedora: {pkg_names['fedora']}")
                enhanced = True
            
            if 'flatpak' in missing_platforms and pkg_names['flatpak']:
                entry['flatpak-pkg'] = pkg_names['flatpak']
                print(f"    Added Flatpak: {pkg_names['flatpak']}")
                enhanced = True
            
            # Update description if it's still a TODO
            if repology_data['description'] and 'TODO' in entry.get('description', ''):
                entry['description'] = repology_data['description']
                print(f"    Updated description")
                enhanced = True
                
            # Track enhanced entries to show later
            if enhanced:
                enhanced_entries[homebrew_pkg] = entry.copy()
        else:
            print(f"    No Repology data found for {homebrew_pkg}")
    
    return enhanced_entries

def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Analyze packages for TOML mappings')
    parser.add_argument('--use-repology', action='store_true', 
                       help='Query Repology API for cross-platform package verification (slower but more accurate)')
    parser.add_argument('--repology-cache', default='repology_cache.json',
                       help='Cache file for Repology API responses')
    args = parser.parse_args()
    # Get the dotfiles directory (assume script is in bin/ subdirectory)
    script_dir = Path(__file__).parent
    dotfiles_dir = script_dir.parent
    
    print(f"Building complete package_mappings.toml from: {dotfiles_dir}")
    print("=" * 70)
    
    # Read existing TOML mappings
    toml_path = dotfiles_dir / "package_mappings.toml"
    homebrew_packages, native_packages = read_toml_mappings(toml_path)
    existing_toml = load_toml(toml_path) if os.path.exists(toml_path) else {}
    
    print(f"Current TOML has {len(homebrew_packages)} homebrew packages")
    
    # Enhance existing TOML entries with Repology data if requested
    enhanced_entries = {}
    if args.use_repology:
        print("\nENHANCING EXISTING TOML ENTRIES:")
        print("-" * 40)
        print(f"Found {len(existing_toml)} existing entries to potentially enhance")
        enhanced_entries = enhance_existing_entries_with_repology(existing_toml, args.repology_cache)
        
        if enhanced_entries:
            print(f"\nENHANCED TOML ENTRIES:")
            print("-" * 40)
            for homebrew_name, entry in sorted(enhanced_entries.items()):
                print(f"\n[{homebrew_name}]")
                for key, value in entry.items():
                    if value or value is False:  # Show non-empty values and explicit False
                        if isinstance(value, bool):
                            print(f"{key} = {str(value).lower()}")
                        else:
                            print(f"{key} = \"{value}\"")
        else:
            print("No existing entries needed enhancement.")
    
    print()
    
    # Collect all packages from existing files that need to be in TOML
    new_packages_by_type = {}
    
    # Read native package files
    arch_packages = read_package_file(dotfiles_dir / "Archfile")
    new_packages_by_type['arch'] = arch_packages - native_packages['arch']
    
    apt_packages = read_package_file(dotfiles_dir / "Aptfile") 
    new_packages_by_type['apt'] = apt_packages - native_packages['apt']
    
    # Check if Fedorafile exists
    fedora_packages = read_package_file(dotfiles_dir / "Fedorafile")
    new_packages_by_type['fedora'] = fedora_packages - native_packages['fedora']
    
    flatpak_packages = read_package_file(dotfiles_dir / "Flatfile")
    new_packages_by_type['flatpak'] = flatpak_packages - native_packages['flatpak']
    
    # Read homebrew files
    all_brew_packages = set()
    
    # Check Brewfile.in
    brewfile_in = dotfiles_dir / "Brewfile.in"
    if os.path.exists(brewfile_in):
        all_brew_packages.update(parse_brewfile(brewfile_in))
    
    # Check Brewfile-darwin files
    brewfile_darwin_files = find_brewfile_darwin_files(dotfiles_dir)
    for brewfile_path in brewfile_darwin_files:
        all_brew_packages.update(parse_brewfile(brewfile_path))
    
    new_packages_by_type['homebrew'] = all_brew_packages - homebrew_packages
    
    # Report what we found
    print("PACKAGES NEEDING TOML ENTRIES:")
    print("-" * 40)
    total_new = 0
    for pkg_type, packages in new_packages_by_type.items():
        if packages:
            print(f"{pkg_type:12}: {len(packages):3} packages")
            total_new += len(packages)
    
    if total_new == 0:
        print("✅ All packages are already in the TOML!")
        return 0
    
    print(f"{'TOTAL':12}: {total_new:3} packages")
    print()
    
    # Suggest consolidations with existing entries
    print("CONSOLIDATION SUGGESTIONS:")
    print("-" * 40)
    suggestions = suggest_consolidation(existing_toml, new_packages_by_type)
    
    if suggestions:
        for suggestion in suggestions:
            if suggestion['action'] == 'add_to_existing':
                print(f"✓ Add {suggestion['add_field']} = \"{suggestion['add_value']}\" to [{suggestion['existing_homebrew']}]")
            elif suggestion['action'] == 'conflict':
                print(f"⚠ CONFLICT in [{suggestion['existing_homebrew']}]: {suggestion['field']}")
                print(f"    Current: {suggestion['existing_value']}")
                print(f"    Found:   {suggestion['new_value']}")
        print()
    else:
        print("No consolidation opportunities found.")
        print()
    
    # Generate new TOML entries for remaining packages
    print("NEW TOML ENTRIES NEEDED:")
    print("-" * 40)
    print("NOTE: Generated entries only include fields for platforms where the package exists.")
    print("      Empty strings indicate the package is deliberately not available on that platform.")
    print("      Platform-specific fields (like arch-is-aur, brew-is-cask) only appear when applicable.")
    print()
    
    # Remove packages that can be consolidated from the new packages lists
    for suggestion in suggestions:
        if suggestion['action'] == 'add_to_existing':
            pkg_type = suggestion['add_field'].replace('-pkg', '')
            if pkg_type in new_packages_by_type:
                new_packages_by_type[pkg_type].discard(suggestion['add_value'])
    
    new_entries = generate_new_toml_entries(new_packages_by_type, existing_toml, args.use_repology, args.repology_cache)
    
    if new_entries:
        print(f"Generated {len(new_entries)} new TOML entries:")
        print()
        for homebrew_name, entry in sorted(new_entries.items()):
            print(f"[{homebrew_name}]")
            for key, value in entry.items():
                if value:  # Only show non-empty values
                    if isinstance(value, bool):
                        print(f"{key} = {str(value).lower()}")
                    else:
                        print(f"{key} = \"{value}\"")
            print()
    else:
        print("No new entries needed after consolidation.")
    
    # Summary
    print("SUMMARY:")
    print("-" * 40)
    print(f"Total packages analyzed: {total_new}")
    print(f"Existing entries enhanced: {len(enhanced_entries)}")
    print(f"Can be consolidated: {len([s for s in suggestions if s['action'] == 'add_to_existing'])}")
    print(f"New entries needed: {len(new_entries)}")
    print(f"Conflicts to resolve: {len([s for s in suggestions if s['action'] == 'conflict'])}")
    
    print("\nNEXT STEPS:")
    if enhanced_entries:
        print("1. Update existing TOML entries with enhanced platform information")
        print("2. Apply consolidation suggestions to existing TOML entries")
        print("3. Add new TOML entries for packages without matches") 
        print("4. Resolve any conflicts manually")
        print("5. Validate the complete TOML can generate all package files")
    else:
        print("1. Apply consolidation suggestions to existing TOML entries")
        print("2. Add new TOML entries for packages without matches") 
        print("3. Resolve any conflicts manually")
        print("4. Validate the complete TOML can generate all package files")
    
    return 1 if (suggestions or new_entries or enhanced_entries) else 0

if __name__ == "__main__":
    sys.exit(main())