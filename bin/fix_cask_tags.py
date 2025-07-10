#!/usr/bin/env python3
"""
Automatically fix incorrect pm:homebrew tags without user interaction
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
        return "No formulae or casks found" not in result.stderr
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return False


def fix_homebrew_tags():
    """Fix incorrect pm:homebrew tags automatically"""
    toml_file = "packages/package_mappings.toml"
    
    if not Path(toml_file).exists():
        print(f"Error: {toml_file} not found")
        return 1
    
    print(f"Fixing incorrect Homebrew tags in {toml_file}...")
    
    # Load TOML
    toml_data = load_toml(toml_file)
    
    # Find packages with pm:homebrew tags
    packages_with_homebrew = []
    for package_name, entry in toml_data.items():
        tags = entry.get("tags", [])
        if any(tag.startswith("pm:homebrew") for tag in tags):
            packages_with_homebrew.append(package_name)
    
    print(f"Found {len(packages_with_homebrew)} packages with pm:homebrew tags")
    
    # Check each package and fix
    fixed_packages = []
    
    for i, package_name in enumerate(packages_with_homebrew, 1):
        print(f"  [{i}/{len(packages_with_homebrew)}] Checking {package_name}...")
        
        if not check_homebrew_package(package_name):
            entry = toml_data[package_name]
            original_tags = entry.get("tags", [])
            
            # Remove all pm:homebrew tags
            new_tags = [tag for tag in original_tags if not tag.startswith("pm:homebrew")]
            
            if len(new_tags) != len(original_tags):
                entry["tags"] = new_tags
                removed_tags = [tag for tag in original_tags if tag.startswith("pm:homebrew")]
                print(f"    ✅ Fixed: Removed {removed_tags}")
                fixed_packages.append(package_name)
            else:
                print(f"    ❌ NOT found in Homebrew but no changes needed")
        else:
            print(f"    ✅ Found in Homebrew - no changes needed")
    
    if fixed_packages:
        # Write the fixed TOML
        print(f"\n💾 Writing fixes to {toml_file}...")
        
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
        
        print(f"✅ Fixed {len(fixed_packages)} packages:")
        for package in fixed_packages:
            print(f"   - {package}")
    else:
        print("No changes needed")
    
    return 0


if __name__ == "__main__":
    sys.exit(fix_homebrew_tags())
