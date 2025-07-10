#!/usr/bin/env python3
"""
Package Manager Tags Audit Tool

MAINTENANCE UTILITY: Audits packages for missing package manager (PM) tags.

PURPOSE:
This tool validates that packages in the TOML have appropriate PM tags (pm:homebrew, 
pm:pacman, pm:apt, pm:flatpak). It's primarily used for debugging and maintenance.

WHEN TO USE:
- After major package system changes to verify PM tag coverage
- When debugging missing package manager information
- To identify packages lacking Repology/Homebrew data
- During system health checks

IMPORTANT NOTES:
- This system relies on authoritative data from Repology and Homebrew APIs
- Missing PM tags usually indicate missing upstream data, not code issues
- Source-file-based tagging is only used as fallback when authoritative data is unavailable
- Packages appearing in multiple source files should have comprehensive PM tag coverage

USAGE:
    python bin/maintenance/audit_missing_pm_tags.py

OUTPUT:
- Lists packages missing expected PM tags
- Shows which source files contain each package
- Provides summary statistics of missing tag types
"""

import sys
from pathlib import Path

# Add lib directory to path
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


def parse_package_lists():
    """Parse package list files to find which packages are in which lists."""
    package_sources = {}
    
    # Parse Brewfile.in
    brewfile_path = Path("packages/Brewfile.in")
    if brewfile_path.exists():
        with open(brewfile_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith('brew "'):
                    start = line.find('"') + 1
                    end = line.find('"', start)
                    if start > 0 and end > start:
                        package = line[start:end]
                        if "/" in package:
                            package = package.split("/")[-1]
                        if package not in package_sources:
                            package_sources[package] = set()
                        package_sources[package].add("homebrew")
    
    # Parse Archfile
    archfile_path = Path("tests/assets/legacy_packages/Archfile")
    if archfile_path.exists():
        with open(archfile_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    if line not in package_sources:
                        package_sources[line] = set()
                    package_sources[line].add("arch")
    
    # Parse Aptfile  
    aptfile_path = Path("tests/assets/legacy_packages/Aptfile")
    if aptfile_path.exists():
        with open(aptfile_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    if line not in package_sources:
                        package_sources[line] = set()
                    package_sources[line].add("apt")
    
    # Parse Flatfile
    flatfile_path = Path("tests/assets/legacy_packages/Flatfile")
    if flatfile_path.exists():
        with open(flatfile_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    if line not in package_sources:
                        package_sources[line] = set()
                    package_sources[line].add("flatpak")
    
    return package_sources


def audit_missing_tags():
    """Check for packages missing expected package manager tags."""
    
    # Load package mappings
    toml_data = load_toml("packages/package_mappings.toml")
    
    # Parse package sources
    package_sources = parse_package_lists()
    
    missing_tags = []
    
    for package_name, sources in package_sources.items():
        if package_name not in toml_data:
            continue
            
        entry = toml_data[package_name]
        current_tags = set(entry.get("tags", []))
        
        # MAINTENANCE NOTE: This audit checks for missing PM tags
        # The system prioritizes authoritative Repology/Homebrew data over source-file-based tags
        # Missing PM tags typically indicate packages lacking upstream API data
        
        pm_tags = [tag for tag in current_tags if tag.startswith("pm:")]
        
        # If a package appears in multiple sources but has no PM tags,
        # that indicates missing Repology/Homebrew data (not a code problem)
        if len(sources) > 0 and len(pm_tags) == 0:
            missing_tags.append({
                "package": package_name,
                "sources": list(sources),
                "missing_tags": ["Any PM tags (indicates missing Repology/Homebrew data)"],
                "current_tags": pm_tags
            })
    
    return missing_tags


def main():
    missing = audit_missing_tags()
    
    if not missing:
        print("✅ All packages have appropriate package manager tags!")
        return 0
    
    print(f"🚨 Found {len(missing)} packages with missing package manager tags:\n")
    
    for item in missing:
        print(f"📦 {item['package']}")
        print(f"   Sources: {', '.join(item['sources'])}")
        print(f"   Current PM tags: {item['current_tags']}")
        print(f"   Missing tags: {', '.join(item['missing_tags'])}")
        print()
    
    # Show summary by missing tag type
    tag_counts = {}
    for item in missing:
        for tag in item['missing_tags']:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1
    
    print("📊 Summary of missing tags:")
    for tag, count in sorted(tag_counts.items()):
        print(f"   {tag}: {count} packages")
    
    return 0


if __name__ == "__main__":
    sys.exit(main())