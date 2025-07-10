#!/usr/bin/env python3
"""
Audit and fix incorrect pm:homebrew tags in package_mappings.toml

This script:
1. Identifies packages with pm:homebrew tags
2. Verifies if they actually exist in Homebrew  
3. Removes incorrect homebrew tags
4. Reports what was fixed
"""

import subprocess
import sys
from pathlib import Path

# Add lib directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))

try:
    import tomllib  # Python 3.11+
    def load_toml(filepath):
        with open(filepath, "rb") as f:
            return tomllib.load(f)
except ImportError:
    try:
        import toml
        def load_toml(filepath):
            with open(filepath) as f:
                return toml.load(f)
    except ImportError:
        def load_toml(filepath):
            raise ImportError("No TOML library available. Install with: pip install toml")


def check_homebrew_package(package_name):
    """Check if a package exists in Homebrew"""
    try:
        result = subprocess.run(
            ["brew", "search", package_name],
            capture_output=True,
            text=True,
            timeout=10
        )
        # If brew search finds the package, it will show it
        # If not found, it will show "No formulae or casks found"
        return "No formulae or casks found" not in result.stderr
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return False


def audit_homebrew_tags(toml_file):
    """Audit pm:homebrew tags in the TOML file"""
    print(f"Auditing Homebrew tags in {toml_file}...")
    
    # Load TOML
    toml_data = load_toml(toml_file)
    
    packages_with_homebrew = []
    
    # Find packages with pm:homebrew tags
    for package_name, entry in toml_data.items():
        tags = entry.get("tags", [])
        if any(tag.startswith("pm:homebrew") for tag in tags):
            packages_with_homebrew.append(package_name)
    
    print(f"Found {len(packages_with_homebrew)} packages with pm:homebrew tags")
    
    # Check each package
    incorrect_packages = []
    correct_packages = []
    
    for i, package_name in enumerate(packages_with_homebrew, 1):
        print(f"  [{i}/{len(packages_with_homebrew)}] Checking {package_name}...")
        
        if check_homebrew_package(package_name):
            correct_packages.append(package_name)
            print(f"    ✅ Found in Homebrew")
        else:
            incorrect_packages.append(package_name)
            print(f"    ❌ NOT found in Homebrew")
    
    print(f"\n📊 Results:")
    print(f"   - Correct homebrew tags: {len(correct_packages)}")
    print(f"   - Incorrect homebrew tags: {len(incorrect_packages)}")
    
    if incorrect_packages:
        print(f"\n🚨 Packages with incorrect pm:homebrew tags:")
        for package in incorrect_packages:
            tags = toml_data[package].get("tags", [])
            homebrew_tags = [tag for tag in tags if tag.startswith("pm:homebrew")]
            print(f"   - {package}: {homebrew_tags}")
    
    return incorrect_packages, correct_packages


def fix_homebrew_tags(toml_file, incorrect_packages):
    """Remove incorrect pm:homebrew tags from packages"""
    if not incorrect_packages:
        print("No incorrect tags to fix!")
        return
    
    print(f"\n🔧 Fixing {len(incorrect_packages)} packages...")
    
    # Load TOML
    toml_data = load_toml(toml_file)
    
    fixed_count = 0
    
    for package_name in incorrect_packages:
        entry = toml_data[package_name]
        original_tags = entry.get("tags", [])
        
        # Remove all pm:homebrew tags
        new_tags = [tag for tag in original_tags if not tag.startswith("pm:homebrew")]
        
        if len(new_tags) != len(original_tags):
            entry["tags"] = new_tags
            removed_tags = [tag for tag in original_tags if tag.startswith("pm:homebrew")]
            print(f"   - {package_name}: Removed {removed_tags}")
            fixed_count += 1
    
    if fixed_count > 0:
        # Write the fixed TOML
        print(f"\n💾 Writing fixes to {toml_file}...")
        
        # Use our existing write function format
        with open(toml_file, "w") as f:
            for package_name, entry in toml_data.items():
                f.write(f"[{package_name}]\n")
                
                # Write description if it exists
                if "description" in entry and entry["description"]:
                    f.write(f'description = "{entry["description"]}"\n')
                
                # Write tags
                tags = entry.get("tags", [])
                if tags:
                    sorted_tags = sorted(set(tags))  # Remove duplicates and sort
                    f.write("tags = [\n")
                    for tag in sorted_tags:
                        f.write(f'    "{tag}",\n')
                    f.write("]\n")
                
                f.write("\n")
        
        print(f"✅ Fixed {fixed_count} packages")
    else:
        print("No changes needed")


def main():
    toml_file = "packages/package_mappings.toml"
    
    if not Path(toml_file).exists():
        print(f"Error: {toml_file} not found")
        return 1
    
    # Audit the tags
    incorrect_packages, correct_packages = audit_homebrew_tags(toml_file)
    
    # Ask if user wants to fix
    if incorrect_packages:
        print(f"\nFound {len(incorrect_packages)} packages with incorrect pm:homebrew tags.")
        response = input("Do you want to remove these incorrect tags? (y/N): ")
        
        if response.lower() in ['y', 'yes']:
            fix_homebrew_tags(toml_file, incorrect_packages)
        else:
            print("No changes made.")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())