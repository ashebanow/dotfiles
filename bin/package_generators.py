#!/usr/bin/env python3
"""
Generate package files from package_mappings.toml.

This tool takes the complete TOML mappings and generates platform-specific package files:
- Brewfile (filtered for current platform)
- Archfile 
- Aptfile
- Flatfile
- Custom package lists

Architecture: TOML → platform detection → filtered package lists
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List, Set, Optional, Any

# Try to import TOML parser
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


def _has_any_packages(entry: Dict[str, Any]) -> bool:
    """Check if a TOML entry has any packages found on any platform."""
    package_fields = ['arch-pkg', 'apt-pkg', 'fedora-pkg', 'flatpak-pkg']
    
    # Check if any package field has a non-empty value
    for field in package_fields:
        if entry.get(field, '').strip():
            return True
    
    # Check homebrew availability (indicated by brew-* fields)
    homebrew_fields = ['brew-supports-darwin', 'brew-supports-linux', 'brew-is-cask']
    if any(entry.get(field) is not None for field in homebrew_fields):
        return True
    
    return False


class PlatformDetector:
    """Detect current platform capabilities."""
    
    def __init__(self):
        self.is_darwin = os.uname().sysname == "Darwin"
        self.is_linux = os.uname().sysname == "Linux"
        
        # Try to detect Linux distribution
        self.is_arch_like = False
        self.is_debian_like = False
        self.is_fedora_like = False
        
        if self.is_linux:
            try:
                with open('/etc/os-release', 'r') as f:
                    os_release = f.read()
                    if 'ID=arch' in os_release or 'ID_LIKE=arch' in os_release:
                        self.is_arch_like = True
                    elif 'ID=debian' in os_release or 'ID_LIKE=debian' in os_release:
                        self.is_debian_like = True
                    elif 'ID=fedora' in os_release or 'ID_LIKE=fedora' in os_release:
                        self.is_fedora_like = True
            except:
                pass  # Can't detect, assume generic Linux
    
    def supports_flatpak(self) -> bool:
        """Check if Flatpak is available on this platform."""
        return self.is_linux  # Flatpak is primarily Linux-only
    
    def supports_homebrew(self) -> bool:
        """Check if Homebrew should be used on this platform."""
        return True  # Homebrew supports both macOS and Linux
    
    def get_native_package_manager(self) -> Optional[str]:
        """Get the native package manager for this platform."""
        if self.is_arch_like:
            return "arch"
        elif self.is_debian_like:
            return "apt"
        elif self.is_fedora_like:
            return "fedora"
        return None


class PackageFilter:
    """Filter packages based on platform availability and priority."""
    
    def __init__(self, toml_data: Dict[str, Any], platform_detector: PlatformDetector):
        self.toml_data = toml_data
        self.platform = platform_detector
    
    def should_use_native_package(self, package_name: str, entry: Dict[str, Any]) -> bool:
        """Check if package should be installed via native package manager."""
        native_pm = self.platform.get_native_package_manager()
        if not native_pm:
            return False
        
        pkg_field = f"{native_pm}-pkg"
        return bool(entry.get(pkg_field, '').strip())
    
    def should_use_flatpak(self, package_name: str, entry: Dict[str, Any]) -> bool:
        """Check if package should be installed via Flatpak."""
        if not self.platform.supports_flatpak():
            return False
        
        flatpak_pkg = entry.get('flatpak-pkg', '').strip()
        if not flatpak_pkg:
            return False
        
        # Only use Flatpak if no native package available or priority is flatpak
        priority = entry.get('priority', 'medium').lower()
        if priority == 'flatpak':
            return True
        
        return not self.should_use_native_package(package_name, entry)
    
    def should_use_homebrew(self, package_name: str, entry: Dict[str, Any]) -> bool:
        """Check if package should be installed via Homebrew."""
        if not self.platform.supports_homebrew():
            return False
        
        # Check if this entry has any packages at all (skip empty entries)
        if not _has_any_packages(entry):
            return False
        
        # Check if Homebrew supports this platform
        if self.platform.is_darwin:
            if not entry.get('brew-supports-darwin', False):
                return False
        elif self.platform.is_linux:
            if not entry.get('brew-supports-linux', False):
                return False
        
        # Use Homebrew if no higher-priority alternatives available
        return not (self.should_use_native_package(package_name, entry) or 
                   self.should_use_flatpak(package_name, entry))
    
    def get_filtered_packages(self, target: str) -> Dict[str, str]:
        """Get packages filtered for specific target (native/flatpak/homebrew)."""
        filtered = {}
        
        for package_name, entry in self.toml_data.items():
            if target == "native":
                if self.should_use_native_package(package_name, entry):
                    native_pm = self.platform.get_native_package_manager()
                    pkg_field = f"{native_pm}-pkg"
                    filtered[package_name] = entry[pkg_field]
            
            elif target == "flatpak":
                if self.should_use_flatpak(package_name, entry):
                    filtered[package_name] = entry['flatpak-pkg']
            
            elif target == "homebrew":
                if self.should_use_homebrew(package_name, entry):
                    # Exclude casks from regular homebrew (they go in homebrew-darwin)
                    if not entry.get('brew-is-cask', False):
                        # Use explicit brew-pkg if available, otherwise use package name
                        brew_name = entry.get('brew-pkg', package_name)
                        filtered[package_name] = brew_name
            
            elif target == "homebrew-darwin":
                # Darwin-specific homebrew packages (usually casks)
                if self.platform.is_darwin:
                    # Skip empty entries
                    if not _has_any_packages(entry):
                        continue
                        
                    # Include packages that are darwin-only or casks
                    is_cask = entry.get('brew-is-cask', False)
                    darwin_only = entry.get('brew-supports-darwin', False) and not entry.get('brew-supports-linux', False)
                    
                    if is_cask or darwin_only:
                        # Don't include if better alternatives exist
                        if not (self.should_use_native_package(package_name, entry) or 
                               self.should_use_flatpak(package_name, entry)):
                            # Use explicit brew-pkg if available, otherwise use package name
                            brew_name = entry.get('brew-pkg', package_name)
                            filtered[package_name] = brew_name
        
        return filtered


class PackageFileGenerator:
    """Generate different package file formats."""
    
    @staticmethod
    def generate_brewfile(packages: Dict[str, str], toml_data: Dict[str, Any], 
                         original_brewfile: str = None, override_file: str = None,
                         include_overrides: bool = True) -> str:
        """Generate Brewfile content with override support."""
        lines = []
        override_packages = set()
        
        # Collect and merge all override packages (auto-generated + manual file)
        # Only include overrides in main Brewfile, not platform-specific ones
        if include_overrides:
            all_override_entries = {}  # pkg_name -> (command_type, actual_name)
            
            # First, collect auto-generated overrides from TOML priority
            for pkg_name, entry in toml_data.items():
                if entry.get('priority') == 'override':
                    is_cask = entry.get('brew-is-cask', False)
                    actual_pkg_name = entry.get('brew-pkg', pkg_name)
                    command_type = 'cask' if is_cask else 'brew'
                    all_override_entries[actual_pkg_name] = (command_type, actual_pkg_name)
                    override_packages.add(actual_pkg_name)
            
            # Then, collect manual overrides from file (can override auto-generated)
            if override_file and os.path.exists(override_file):
                with open(override_file, 'r') as f:
                    for line in f:
                        line = line.strip()
                        if line and not line.startswith('#'):
                            if line.startswith('brew "') or line.startswith('cask "'):
                                parts = line.split('"')
                                if len(parts) >= 2:
                                    command_type = 'cask' if line.startswith('cask') else 'brew'
                                    pkg_name = parts[1]
                                    all_override_entries[pkg_name] = (command_type, pkg_name)
                                    override_packages.add(pkg_name)
            
            # Write merged and deduplicated override packages
            if all_override_entries:
                lines.append("# Override packages (critical infrastructure and platform-specific overrides)")
                for pkg_name in sorted(all_override_entries.keys()):
                    command_type, actual_name = all_override_entries[pkg_name]
                    lines.append(f'{command_type} "{actual_name}"')
                lines.append("")  # Empty line after overrides
        
        # Add taps from original file if available
        if original_brewfile and os.path.exists(original_brewfile):
            with open(original_brewfile, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('tap '):
                        lines.append(line)
        
        lines.append("")  # Empty line after taps
        
        # Add platform-specific brew packages (skip if already in overrides)
        lines.append("# Platform-specific packages")
        for package_name in sorted(packages.keys()):
            if package_name in override_packages:
                continue  # Skip packages already in overrides
                
            entry = toml_data[package_name]
            is_cask = entry.get('brew-is-cask', False)
            # Use the actual package name from filtered results
            actual_package_name = packages[package_name]
            
            if is_cask:
                lines.append(f'cask "{actual_package_name}"')
            else:
                lines.append(f'brew "{actual_package_name}"')
        
        return '\n'.join(lines) + '\n'
    
    @staticmethod
    def generate_simple_list(packages: Dict[str, str]) -> str:
        """Generate simple package list (one per line)."""
        return '\n'.join(sorted(packages.values())) + '\n'
    
    @staticmethod
    def generate_archfile(packages: Dict[str, str], toml_data: Dict[str, Any]) -> str:
        """Generate Archfile with AUR comments."""
        lines = []
        
        for package_name in sorted(packages.keys()):
            entry = toml_data[package_name]
            pkg_name = packages[package_name]
            
            if entry.get('arch-is-aur', False):
                lines.append(f"{pkg_name}  # AUR")
            else:
                lines.append(pkg_name)
        
        return '\n'.join(lines) + '\n'


def should_regenerate_files(toml_path: str, output_dir: str, 
                           original_brewfile: str = None) -> bool:
    """Check if package files need regeneration based on file ages."""
    if not output_dir or not os.path.exists(output_dir):
        return True  # Output directory doesn't exist, need to regenerate
    
    # Get source file modification times
    source_files = [toml_path]
    if original_brewfile and os.path.exists(original_brewfile):
        source_files.append(original_brewfile)
    
    # Add Brewfile-overrides if it exists
    toml_dir = Path(toml_path).parent
    override_file = toml_dir / "Brewfile-overrides"
    if override_file.exists():
        source_files.append(str(override_file))
    
    # Get newest source file time
    newest_source_time = 0
    for source_file in source_files:
        if os.path.exists(source_file):
            newest_source_time = max(newest_source_time, os.path.getmtime(source_file))
    
    # Get expected output files based on platform (simulate what would be generated)
    platform = PlatformDetector()
    output_path = Path(output_dir)
    expected_files = []
    
    # Always check for Homebrew files
    if output_path.joinpath('Brewfile').exists():
        expected_files.append('Brewfile')
    if platform.is_darwin and output_path.joinpath('Brewfile-darwin').exists():
        expected_files.append('Brewfile-darwin')
    
    # Check for native package manager files
    native_pm = platform.get_native_package_manager()
    if native_pm == "arch" and output_path.joinpath('Archfile').exists():
        expected_files.append('Archfile')
    elif native_pm == "apt" and output_path.joinpath('Aptfile').exists():
        expected_files.append('Aptfile')
    elif native_pm == "fedora" and output_path.joinpath('Fedorafile').exists():
        expected_files.append('Fedorafile')
    
    # Check for Flatpak file
    if platform.supports_flatpak() and output_path.joinpath('Flatfile').exists():
        expected_files.append('Flatfile')
    
    # If no expected files exist, need to regenerate
    if not expected_files:
        return True
    
    # Check if any expected output files are older than newest source
    for filename in expected_files:
        file_path = output_path / filename
        if os.path.getmtime(file_path) < newest_source_time:
            return True  # At least one output file is older
    
    return False  # All expected output files are newer than sources


def generate_package_files(toml_path: str, output_dir: str = None, 
                          original_brewfile: str = None, force: bool = False) -> Dict[str, str]:
    """Generate all package files from TOML."""
    
    # Check if regeneration is needed (unless forced)
    if not force and output_dir and not should_regenerate_files(toml_path, output_dir, original_brewfile):
        print("All output files are up-to-date, skipping regeneration")
        print("Use --force to regenerate anyway")
        return {}
    
    # Load TOML data
    toml_data = load_toml(toml_path)
    print(f"Loaded {len(toml_data)} packages from {toml_path}")
    
    # Initialize platform detection and filtering
    platform = PlatformDetector()
    package_filter = PackageFilter(toml_data, platform)
    generator = PackageFileGenerator()
    
    print(f"Platform: Darwin={platform.is_darwin}, Linux={platform.is_linux}")
    print(f"Native PM: {platform.get_native_package_manager()}")
    
    # Get filtered packages
    native_packages = package_filter.get_filtered_packages("native")
    flatpak_packages = package_filter.get_filtered_packages("flatpak")
    homebrew_packages = package_filter.get_filtered_packages("homebrew")
    
    # Get Darwin-specific packages if on macOS
    homebrew_darwin_packages = {}
    if platform.is_darwin:
        homebrew_darwin_packages = package_filter.get_filtered_packages("homebrew-darwin")
    
    print(f"Filtered packages: Native={len(native_packages)}, Flatpak={len(flatpak_packages)}, Homebrew={len(homebrew_packages)}")
    if homebrew_darwin_packages:
        print(f"Darwin-specific: {len(homebrew_darwin_packages)}")
    
    # Generate file contents
    generated_files = {}
    
    # Homebrew files
    if homebrew_packages:
        # Look for override file in the same directory as TOML
        toml_dir = Path(toml_path).parent
        override_file = toml_dir / "Brewfile-overrides"
        
        brewfile_content = generator.generate_brewfile(
            homebrew_packages, toml_data, original_brewfile, str(override_file)
        )
        generated_files['Brewfile'] = brewfile_content
    
    # Darwin-specific Homebrew file
    if homebrew_darwin_packages and platform.is_darwin:
        brewfile_darwin_content = generator.generate_brewfile(
            homebrew_darwin_packages, toml_data, None, None, include_overrides=False  # No taps or overrides for darwin-specific file
        )
        generated_files['Brewfile-darwin'] = brewfile_darwin_content
    
    # Native package files
    if native_packages:
        native_pm = platform.get_native_package_manager()
        if native_pm == "arch":
            archfile_content = generator.generate_archfile(native_packages, toml_data)
            generated_files['Archfile'] = archfile_content
        elif native_pm == "apt":
            aptfile_content = generator.generate_simple_list(native_packages)
            generated_files['Aptfile'] = aptfile_content
        elif native_pm == "fedora":
            fedorafile_content = generator.generate_simple_list(native_packages)
            generated_files['Fedorafile'] = fedorafile_content
    
    # Flatpak file
    if flatpak_packages and platform.supports_flatpak():
        flatfile_content = generator.generate_simple_list(flatpak_packages)
        generated_files['Flatfile'] = flatfile_content
    
    # Write files if output directory specified
    if output_dir:
        output_path = Path(output_dir)
        output_path.mkdir(exist_ok=True)
        
        for filename, content in generated_files.items():
            file_path = output_path / filename
            with open(file_path, 'w') as f:
                f.write(content)
            print(f"Generated: {file_path}")
    
    return generated_files


def main():
    parser = argparse.ArgumentParser(description='Generate package files from TOML mappings')
    
    # Input options
    parser.add_argument('--toml', '-t',
                       help='Path to package_mappings.toml file')
    parser.add_argument('--original-brewfile',
                       help='Original Brewfile.in for preserving taps')
    
    # Output options
    parser.add_argument('--output-dir', '-o',
                       help='Directory to write generated package files')
    parser.add_argument('--print-only', action='store_true',
                       help='Print generated files to stdout instead of writing')
    
    # Filter options
    parser.add_argument('--target', choices=['native', 'flatpak', 'homebrew', 'homebrew-darwin', 'all'],
                       default='all',
                       help='Generate files for specific package manager only')
    parser.add_argument('--force', '-f', action='store_true',
                       help='Force regeneration even if output files are newer than source files')
    
    args = parser.parse_args()
    
    # Get script directory for default paths
    script_dir = Path(__file__).parent
    dotfiles_dir = script_dir.parent
    
    # Set default TOML path
    if not args.toml:
        default_toml = dotfiles_dir / "package_mappings.toml"
        if default_toml.exists():
            args.toml = str(default_toml)
        else:
            print(f"Error: No TOML file found at {default_toml}")
            sys.exit(1)
    
    # Set default original Brewfile
    if not args.original_brewfile:
        default_brewfile = dotfiles_dir / "Brewfile.in"
        if default_brewfile.exists():
            args.original_brewfile = str(default_brewfile)
    
    print("=== Package Generator ===")
    print(f"TOML file: {args.toml}")
    print(f"Original Brewfile: {args.original_brewfile or 'None'}")
    print(f"Target: {args.target}")
    print()
    
    # Generate package files
    try:
        generated_files = generate_package_files(
            toml_path=args.toml,
            output_dir=args.output_dir if not args.print_only else None,
            original_brewfile=args.original_brewfile,
            force=args.force
        )
        
        # Print files if requested
        if args.print_only:
            for filename, content in generated_files.items():
                print(f"\n=== {filename} ===")
                print(content)
        
        print(f"\nSUMMARY: Generated {len(generated_files)} package files")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    sys.exit(main())