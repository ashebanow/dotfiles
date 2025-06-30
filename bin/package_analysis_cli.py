#!/usr/bin/env python3
"""
CLI wrapper for package analysis with tagging support.

This script provides the command-line interface that tests expect,
while using the new tagging system internally.
"""

import argparse
import sys
import json
from pathlib import Path

# Add lib directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
sys.path.insert(0, str(Path(__file__).parent))

try:
    from package_analysis_tagged import enhance_package_entry_with_tags
except ImportError as e:
    print(f"Error importing package_analysis_tagged: {e}")
    sys.exit(1)

# Import TOML handling
try:
    import tomllib  # Python 3.11+

    def load_toml(filepath):
        try:
            with open(filepath, "rb") as f:
                return tomllib.load(f)
        except (FileNotFoundError, tomllib.TOMLDecodeError, OSError) as e:
            print(f"Error loading TOML file: {e}")
            return {}

except ImportError:
    try:
        import toml

        def load_toml(filepath):
            try:
                with open(filepath) as f:
                    return toml.load(f)
            except (FileNotFoundError, toml.TomlDecodeError, OSError) as e:
                print(f"Error loading TOML file: {e}")
                return {}

    except ImportError:
        print("No TOML library available. Install with: pip install toml")
        sys.exit(1)

def write_toml(data: dict, filepath: str) -> None:
    """Write TOML data with proper formatting."""
    with open(filepath, "w") as f:
        for package_name in sorted(data.keys()):
            entry = data[package_name]

            # Section header
            if "." in package_name or "@" in package_name:
                f.write(f'["{package_name}"]\n')
            else:
                f.write(f"[{package_name}]\n")

            # Write fields in order
            for key, value in entry.items():
                if isinstance(value, bool):
                    f.write(f'{key} = {str(value).lower()}\n')
                elif isinstance(value, list):
                    if value:  # Only write non-empty lists
                        formatted_list = ', '.join([f'"{item}"' for item in value])
                        f.write(f'{key} = [{formatted_list}]\n')
                elif value or value == "":  # Include empty strings
                    f.write(f'{key} = "{value}"\n')
            f.write("\n")

def create_basic_package_entry(package_name: str) -> dict:
    """Create a basic package entry that can be enhanced with tags."""
    return {
        "arch-pkg": "",
        "apt-pkg": "",
        "fedora-pkg": "",
        "flatpak-pkg": "",
        "brew-tap": "",
        "prefer_flatpak": False,
        "priority": "",
        "description": f"TODO: Add description for {package_name}",
        "custom-install": "",
        "tags": []
    }

def analyze_packages(package_names: list, output_file: str = None, cache_file: str = None):
    """Analyze packages and generate TOML entries."""
    results = {}
    
    for package_name in package_names:
        print(f"Analyzing package: {package_name}")
        
        # Create basic entry
        entry = create_basic_package_entry(package_name)
        
        # Enhance with tags
        try:
            enhanced_entry = enhance_package_entry_with_tags(package_name, entry)
            results[package_name] = enhanced_entry
        except Exception as e:
            print(f"Warning: Could not enhance {package_name} with tags: {e}")
            results[package_name] = entry
    
    if output_file:
        write_toml(results, output_file)
        print(f"Results written to {output_file}")
    else:
        # Print to stdout
        for name, entry in results.items():
            print(f"\n[{name}]")
            for key, value in entry.items():
                if isinstance(value, bool):
                    print(f'{key} = {str(value).lower()}')
                elif isinstance(value, list):
                    if value:  # Only print non-empty lists
                        formatted_list = ', '.join([f'"{item}"' for item in value])
                        print(f'{key} = [{formatted_list}]')
                else:
                    print(f'{key} = "{value}"')

def parse_package_lists(package_lists: list):
    """Parse package list files and return set of package names."""
    all_packages = set()
    
    for package_list in package_lists:
        if not Path(package_list).exists():
            print(f"Warning: Package list file not found: {package_list}")
            continue
            
        with open(package_list) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    # Handle Brewfile format
                    if line.startswith('brew "'):
                        # Extract package name from brew "package-name"
                        start = line.find('"') + 1
                        end = line.find('"', start)
                        if start > 0 and end > start:
                            package = line[start:end]
                            if '/' in package:
                                package = package.split('/')[-1]
                            all_packages.add(package)
                    else:
                        # Simple package list format
                        all_packages.add(line)
    
    return all_packages

def main():
    parser = argparse.ArgumentParser(
        description="Generate package mappings with tagging support"
    )
    
    parser.add_argument(
        "--package", 
        nargs="+", 
        help="Process specific packages only"
    )
    parser.add_argument(
        "--package-lists", 
        nargs="+", 
        help="Package list files to process"
    )
    parser.add_argument(
        "--output", "-o", 
        help="Write TOML to file"
    )
    parser.add_argument(
        "--cache", 
        help="Cache file (for compatibility, not used)"
    )
    parser.add_argument(
        "--existing-toml", 
        help="Existing TOML file (for compatibility, not used)"
    )
    parser.add_argument(
        "--validate", 
        action="store_true", 
        help="Validate mode (not implemented)"
    )
    
    args = parser.parse_args()
    
    if args.validate:
        print("Validation mode not implemented in CLI wrapper")
        return 1
    
    if args.package:
        # Analyze specific packages
        analyze_packages(args.package, args.output, args.cache)
    elif args.package_lists:
        # Parse package lists and analyze all packages
        all_packages = parse_package_lists(args.package_lists)
        if all_packages:
            analyze_packages(list(all_packages), args.output, args.cache)
        else:
            print("No packages found in package lists")
            return 1
    else:
        print("Error: Must specify either --package or --package-lists")
        return 1
    
    return 0

if __name__ == "__main__":
    sys.exit(main())