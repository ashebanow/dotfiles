#!/usr/bin/env python3
"""
CLI wrapper for package analysis with tagging support.

This script provides the command-line interface that tests expect,
while using the new tagging system internally.
"""

import argparse
import json
import sys
from pathlib import Path

# Add lib directory to path
sys.path.insert(0, str(Path(__file__).parent.parent / "lib"))
sys.path.insert(0, str(Path(__file__).parent))

try:
    from package_analysis_tagged import enhance_package_entry_with_tags
    from tag_cache_utils import TagCache
    from homebrew_client import HomebrewClient
except ImportError as e:
    print(f"Error importing required modules: {e}")
    sys.exit(1)


class RepologyCache:
    """Simple cache reader for existing Repology cache format."""

    def __init__(self, cache_file: str = None):
        self.cache = {}
        self.name_mappings = {}

        if cache_file and Path(cache_file).exists():
            try:
                with open(cache_file) as f:
                    self.cache = json.load(f)
            except Exception as e:
                print(f"Warning: Could not load Repology cache: {e}")

        # Load package name mappings
        cache_dir = Path(cache_file).parent if cache_file else Path("packages")
        mappings_file = cache_dir / "package_name_mappings.json"
        if mappings_file.exists():
            try:
                with open(mappings_file) as f:
                    mappings_data = json.load(f)
                    self.name_mappings = mappings_data.get("homebrew_to_repology", {})
            except Exception as e:
                print(f"Warning: Could not load package name mappings: {e}")

    def get_package_data(self, package_name: str) -> dict:
        """Get cached data for a package, checking name mappings."""
        # First try direct lookup
        data = self.cache.get(package_name, {})

        # If not found, try mapped name
        if not data and package_name in self.name_mappings:
            mapped_name = self.name_mappings[package_name]
            data = self.cache.get(mapped_name, {})
            if data:
                print(f"  Using mapped name: {package_name} -> {mapped_name}")

        return data

    def query_package(self, package_name: str) -> dict:
        """Query method for compatibility with enhance_package_entry_with_tags."""
        data = self.get_package_data(package_name)
        # Return None if no data or all platforms are false
        if not data:
            return None
        platforms = data.get("platforms", {})
        if all(not v for v in platforms.values()):
            return None
        return data


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

            # Write fields in order - description first if it exists and is not empty
            if "description" in entry and entry["description"]:
                f.write(f'description = "{entry["description"]}"\n')
            
            # Then tags with proper formatting
            if "tags" in entry and entry["tags"]:
                tags = entry["tags"]
                # Remove duplicates and sort tags alphabetically
                sorted_tags = sorted(set(tags))
                
                # Format with one tag per line
                if len(sorted_tags) == 1:
                    # Single tag on one line
                    f.write(f'tags = ["{sorted_tags[0]}"]\n')
                else:
                    # Multiple lines with one tag per line
                    f.write(f"tags = [\n")
                    for i, tag in enumerate(sorted_tags):
                        if i < len(sorted_tags) - 1:
                            f.write(f'    "{tag}",\n')
                        else:
                            f.write(f'    "{tag}"\n')
                    f.write("]\n")
            
            # Write other fields (skip obsolete ones and defaults)
            for key, value in entry.items():
                if key in ["description", "tags"]:
                    continue  # Already handled above
                if isinstance(value, bool):
                    if value:  # Only write non-default booleans
                        f.write(f"{key} = {str(value).lower()}\n")
                elif isinstance(value, list):
                    if value:  # Only write non-empty lists
                        formatted_list = ", ".join([f'"{item}"' for item in value])
                        f.write(f"{key} = [{formatted_list}]\n")
                elif value:  # Only write non-empty strings
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
        "custom-install": "",
        "tags": [],
    }


def analyze_packages(
    package_info: dict,
    output_file: str = None,
    cache_file: str = None,
    tag_cache_file: str = None,
    use_tag_cache: bool = True,
):
    """Analyze packages and generate TOML entries."""
    results = {}

    # Load Repology cache if available
    repology_client = None
    if cache_file:
        repology_client = RepologyCache(cache_file)
        print(f"Loaded Repology cache with {len(repology_client.cache)} entries")

    # Initialize Homebrew client for description fallback
    homebrew_client = HomebrewClient()
    if homebrew_client.is_available():
        print("Homebrew available for description fallback")
    else:
        print("Homebrew not available - skipping description fallback")
        homebrew_client = None

    # Load tag cache if enabled
    tag_cache = None
    if use_tag_cache:
        if not tag_cache_file:
            # Default location in packages directory
            tag_cache_file = (
                str(Path(cache_file).parent / "tag_cache.json") if cache_file else "tag_cache.json"
            )
        tag_cache = TagCache(tag_cache_file)
        stats = tag_cache.get_stats()
        print(f"Loaded tag cache with {stats['fresh_entries']} fresh entries")

    cache_hits = 0
    cache_misses = 0

    for package_name, metadata in package_info.items():
        print(f"Analyzing package: {package_name}")

        # Create basic entry
        entry = create_basic_package_entry(package_name)

        # Add appropriate tags based on source files and type
        source_files = metadata.get("source_files", [])
        if metadata.get("is_cask", False):
            # Casks are macOS-only GUI applications
            entry["tags"].append("cat:cask")
            entry["tags"].append("os:macos")
        else:
            # Add tags for each source file the package appears in
            for source_file in source_files:
                if source_file == "Brewfile.in":
                    # Brewfile.in contains cross-platform homebrew packages
                    if "pm:homebrew" not in entry["tags"]:
                        entry["tags"].append("pm:homebrew")
                elif source_file == "Brewfile-darwin":
                    # Non-cask packages from Brewfile-darwin are macOS-only
                    if "pm:homebrew:darwin" not in entry["tags"]:
                        entry["tags"].append("pm:homebrew:darwin")
                    if "os:macos" not in entry["tags"]:
                        entry["tags"].append("os:macos")
                elif source_file == "Archfile":
                    # Packages from Archfile need pacman tags
                    if "pm:pacman" not in entry["tags"]:
                        entry["tags"].append("pm:pacman")
                    if "os:linux" not in entry["tags"]:
                        entry["tags"].append("os:linux")
                    if "dist:arch" not in entry["tags"]:
                        entry["tags"].append("dist:arch")
                elif source_file == "Aptfile":
                    # Packages from Aptfile need apt tags
                    if "pm:apt" not in entry["tags"]:
                        entry["tags"].append("pm:apt")
                    if "os:linux" not in entry["tags"]:
                        entry["tags"].append("os:linux")
                    if "dist:debian" not in entry["tags"]:
                        entry["tags"].append("dist:debian")
                    if "dist:ubuntu" not in entry["tags"]:
                        entry["tags"].append("dist:ubuntu")
                elif source_file == "Flatfile":
                    # Packages from Flatfile need flatpak tags
                    if "pm:flatpak" not in entry["tags"]:
                        entry["tags"].append("pm:flatpak")
                    if "os:linux" not in entry["tags"]:
                        entry["tags"].append("os:linux")
        # Don't add default homebrew tags for non-homebrew sources

        # Check tag cache first
        cached_tags = None
        repology_timestamp = None

        if tag_cache and repology_client:
            # Get Repology data timestamp
            repology_data = repology_client.get_package_data(package_name)
            repology_timestamp = repology_data.get("_timestamp") if repology_data else None

            # Try to get cached tags
            cached_tags = tag_cache.get_tags(package_name, repology_timestamp)

        if cached_tags is not None:
            # Use cached tags but ensure cask tags are preserved
            if metadata.get("is_cask", False):
                cached_tags = list(set(cached_tags + ["cat:cask", "os:macos"]))
            entry["tags"] = cached_tags
            
            # Even with cached tags, we should try to get description if missing
            if not entry.get("description", "").strip():
                # Try Repology first
                repology_desc = repology_data.get("description") if repology_data else None
                if repology_desc and repology_desc.strip():
                    entry["description"] = repology_desc.strip()
                # Fall back to Homebrew if needed
                elif homebrew_client:
                    try:
                        homebrew_description = homebrew_client.get_package_description(package_name)
                        if homebrew_description:
                            entry["description"] = homebrew_description
                    except Exception as e:
                        print(f"Warning: Homebrew description lookup failed for {package_name}: {e}")
            
            results[package_name] = entry
            cache_hits += 1
        else:
            # Compute tags
            try:
                enhanced_entry = enhance_package_entry_with_tags(
                    package_name, entry, repology_client=repology_client, homebrew_client=homebrew_client
                )
                results[package_name] = enhanced_entry
                cache_misses += 1

                # Cache the computed tags
                if tag_cache:
                    tag_cache.set_tags(
                        package_name, enhanced_entry.get("tags", []), repology_timestamp
                    )

            except Exception as e:
                print(f"Warning: Could not enhance {package_name} with tags: {e}")
                results[package_name] = entry

    # Save tag cache if modified
    if tag_cache:
        tag_cache.save()
        print(f"Tag cache stats: {cache_hits} hits, {cache_misses} misses")

    if output_file:
        write_toml(results, output_file)
        print(f"Results written to {output_file}")
    else:
        # Print to stdout
        for name, entry in results.items():
            print(f"\n[{name}]")
            for key, value in entry.items():
                if isinstance(value, bool):
                    print(f"{key} = {str(value).lower()}")
                elif isinstance(value, list):
                    if value:  # Only print non-empty lists
                        formatted_list = ", ".join([f'"{item}"' for item in value])
                        print(f"{key} = [{formatted_list}]")
                else:
                    print(f'{key} = "{value}"')


def parse_package_lists(package_lists: list):
    """Parse package list files and return dict of package names with metadata."""
    all_packages = {}

    for package_list in package_lists:
        if not Path(package_list).exists():
            print(f"Warning: Package list file not found: {package_list}")
            continue

        # Track which file we're processing
        filename = Path(package_list).name

        with open(package_list) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    # Handle Brewfile format
                    if line.startswith('tap "'):
                        # Skip tap lines - they're repository references, not packages
                        continue
                    elif line.startswith('brew "'):
                        # Extract package name from brew "package-name"
                        start = line.find('"') + 1
                        end = line.find('"', start)
                        if start > 0 and end > start:
                            package = line[start:end]
                            if "/" in package:
                                package = package.split("/")[-1]
                            # Track all source files for this package
                            if package not in all_packages:
                                all_packages[package] = {"is_cask": False, "source_files": []}
                            all_packages[package]["source_files"].append(filename)
                    elif line.startswith('cask "'):
                        # Extract package name from cask "package-name"
                        start = line.find('"') + 1
                        end = line.find('"', start)
                        if start > 0 and end > start:
                            package = line[start:end]
                            if package not in all_packages:
                                all_packages[package] = {"is_cask": True, "source_files": []}
                            all_packages[package]["source_files"].append(filename)
                    else:
                        # Simple package list format
                        if line not in all_packages:
                            all_packages[line] = {"is_cask": False, "source_files": []}
                        all_packages[line]["source_files"].append(filename)

    return all_packages


def main():
    parser = argparse.ArgumentParser(description="Generate package mappings with tagging support")

    parser.add_argument("--package", nargs="+", help="Process specific packages only")
    parser.add_argument("--package-lists", nargs="+", help="Package list files to process")
    parser.add_argument("--output", "-o", help="Write TOML to file")
    parser.add_argument("--cache", help="Repology cache file to use for enhanced tag generation")
    parser.add_argument(
        "--tag-cache", help="Tag cache file (defaults to tag_cache.json in same dir as --cache)"
    )
    parser.add_argument("--no-tag-cache", action="store_true", help="Disable tag caching")
    parser.add_argument("--existing-toml", help="Existing TOML file (for compatibility, not used)")
    parser.add_argument("--validate", action="store_true", help="Validate mode (not implemented)")

    args = parser.parse_args()

    if args.validate:
        print("Validation mode not implemented in CLI wrapper")
        return 1

    if args.package:
        # Analyze specific packages - convert to dict format
        package_info = {pkg: {"is_cask": False} for pkg in args.package}
        analyze_packages(
            package_info,
            args.output,
            args.cache,
            tag_cache_file=args.tag_cache,
            use_tag_cache=not args.no_tag_cache,
        )
    elif args.package_lists:
        # Parse package lists and analyze all packages
        all_packages = parse_package_lists(args.package_lists)
        if all_packages:
            analyze_packages(
                all_packages,
                args.output,
                args.cache,
                tag_cache_file=args.tag_cache,
                use_tag_cache=not args.no_tag_cache,
            )
        else:
            print("No packages found in package lists")
            return 1
    else:
        print("Error: Must specify either --package or --package-lists")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
