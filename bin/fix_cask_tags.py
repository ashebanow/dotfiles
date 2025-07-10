#!/usr/bin/env python3
"""
Fix package manager tags for packages that appear in multiple package lists.

This script addresses the issue where packages appearing in multiple package lists
(e.g., both Brewfile and Archfile) only get tags from the last processed file.
"""

import sys
from pathlib import Path

# Add lib directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

# Import TOML handling
try:
    import tomllib  # Python 3.11+

    def load_toml(filepath):
        with open(filepath, "rb") as f:
            return tomllib.load(f)
            
    def dump_toml(data, filepath):
        # tomllib doesn't have a write function, use toml instead
        import toml
        with open(filepath, "w") as f:
            toml.dump(data, f)

except ImportError:
    try:
        import toml

        def load_toml(filepath):
            with open(filepath) as f:
                return toml.load(f)
                
        def dump_toml(data, filepath):
            with open(filepath, "w") as f:
                toml.dump(data, f)

    except ImportError:
        print("Error: No TOML library available. Install with: pip install toml")
        sys.exit(1)


def get_packages_from_file(filepath):
    """Extract package names from a package list file."""
    packages = set()
    
    if not Path(filepath).exists():
        return packages
        
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                # Handle Brewfile format
                if line.startswith('tap "'):
                    continue
                elif line.startswith('brew "'):
                    # Extract package name from brew "package-name"
                    start = line.find('"') + 1
                    end = line.find('"', start)
                    if start > 0 and end > start:
                        package = line[start:end]
                        if "/" in package:
                            package = package.split("/")[-1]
                        packages.add(package)
                elif line.startswith('cask "'):
                    # Skip casks - they're handled separately
                    continue
                else:
                    # Simple package list format (Archfile, Aptfile, etc.)
                    packages.add(line)
                    
    return packages


def main():
    # Load current package mappings
    toml_path = Path("packages/package_mappings.toml")
    if not toml_path.exists():
        print(f"Error: {toml_path} not found")
        sys.exit(1)
        
    data = load_toml(toml_path)
    
    # Get packages from each source
    brewfile_packages = get_packages_from_file("packages/Brewfile.in")
    archfile_packages = get_packages_from_file("tests/assets/legacy_packages/Archfile")
    aptfile_packages = get_packages_from_file("tests/assets/legacy_packages/Aptfile")
    flatfile_packages = get_packages_from_file("tests/assets/legacy_packages/Flatfile")
    
    print(f"Found {len(brewfile_packages)} packages in Brewfile.in")
    print(f"Found {len(archfile_packages)} packages in Archfile")
    print(f"Found {len(aptfile_packages)} packages in Aptfile")
    print(f"Found {len(flatfile_packages)} packages in Flatfile")
    
    # Find packages that need additional PM tags
    packages_fixed = 0
    
    for package_name, entry in data.items():
        if package_name == "settings":  # Skip the settings section
            continue
            
        tags = entry.get("tags", [])
        pm_tags = [tag for tag in tags if tag.startswith("pm:")]
        
        # Check which package lists this package appears in
        needs_tags = []
        
        if package_name in archfile_packages and "pm:pacman" not in tags:
            needs_tags.append("pm:pacman")
            needs_tags.append("os:linux")
            needs_tags.append("dist:arch")
            
        if package_name in aptfile_packages and "pm:apt" not in tags:
            needs_tags.append("pm:apt")
            needs_tags.append("os:linux")
            needs_tags.append("dist:debian")
            needs_tags.append("dist:ubuntu")
            
        if package_name in flatfile_packages and "pm:flatpak" not in tags:
            needs_tags.append("pm:flatpak")
            needs_tags.append("os:linux")
            
        if package_name in brewfile_packages and not any(tag.startswith("pm:homebrew") for tag in tags):
            # Only add generic homebrew tag if it's in Brewfile.in
            needs_tags.append("pm:homebrew")
            
        if needs_tags:
            print(f"\nFixing {package_name}:")
            print(f"  Current PM tags: {pm_tags}")
            print(f"  Adding tags: {needs_tags}")
            
            # Add new tags while preserving order and avoiding duplicates
            for tag in needs_tags:
                if tag not in tags:
                    # Insert PM tags after category tags but before priority tags
                    insert_pos = len(tags)
                    for i, existing_tag in enumerate(tags):
                        if existing_tag.startswith("priority:") or existing_tag.startswith("scope:"):
                            insert_pos = i
                            break
                    tags.insert(insert_pos, tag)
                    
            entry["tags"] = tags
            packages_fixed += 1
    
    if packages_fixed > 0:
        # Save the updated TOML
        dump_toml(data, toml_path)
        print(f"\nFixed {packages_fixed} packages in {toml_path}")
    else:
        print("\nNo packages needed fixing")
        
    # Specifically check zsh-completions
    if "zsh-completions" in data:
        print(f"\nzsh-completions tags: {data['zsh-completions'].get('tags', [])}")


if __name__ == "__main__":
    main()