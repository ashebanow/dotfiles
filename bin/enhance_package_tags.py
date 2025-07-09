#!/usr/bin/env python3
"""
Automatically enhance package tags based on Repology cache data and existing package fields.
"""

import json
import sys
from pathlib import Path

import toml


def load_data():
    """Load TOML and cache data."""
    toml_path = Path("packages/package_mappings.toml")
    cache_path = Path("packages/repology_cache.json")

    if not toml_path.exists():
        print(f"Error: {toml_path} not found")
        sys.exit(1)

    if not cache_path.exists():
        print(f"Error: {cache_path} not found")
        sys.exit(1)

    with open(toml_path) as f:
        toml_data = toml.load(f)

    with open(cache_path) as f:
        cache_data = json.load(f)

    return toml_data, cache_data


def enhance_package_tags(package_name, package_data, cache_data):
    """Enhance tags for a single package."""
    current_tags = set(package_data.get("tags", []))
    new_tags = set()

    # Get cache entry if available
    cache_entry = cache_data.get(package_name, {})
    platforms = cache_entry.get("platforms", {})

    # Track if we have cache data
    has_cache_data = bool(cache_entry)

    # Add OS tags based on cache data
    if (
        platforms.get("homebrew")
        or cache_entry.get("brew-supports-darwin")
        or cache_entry.get("brew-is-cask")
    ):
        new_tags.add("os:macos")

    if (
        platforms.get("arch_official")
        or platforms.get("arch_aur")
        or platforms.get("debian")
        or platforms.get("ubuntu")
        or platforms.get("fedora")
        or platforms.get("flatpak")
    ):
        new_tags.add("os:linux")

    # Add OS tags based on existing package fields
    if package_data.get("arch-pkg"):
        new_tags.add("os:linux")

    if package_data.get("apt-pkg"):
        new_tags.add("os:linux")

    if package_data.get("fedora-pkg"):
        new_tags.add("os:linux")

    # Add PM tags based on cache data
    if cache_entry.get("brew-is-cask", False):
        new_tags.add("pm:homebrew:cask")
        new_tags.add("os:macos")  # Casks are macOS-only
    elif platforms.get("homebrew"):
        # Determine if it's Darwin/Linux specific
        darwin_support = cache_entry.get("brew-supports-darwin", False)
        linux_support = cache_entry.get("brew-supports-linux", False)

        if darwin_support and linux_support:
            new_tags.add("pm:homebrew")
        elif darwin_support:
            new_tags.add("pm:homebrew:darwin")
        elif linux_support:
            new_tags.add("pm:homebrew:linux")
        else:
            new_tags.add("pm:homebrew")  # Default fallback

    if platforms.get("arch_official") or platforms.get("arch_aur"):
        new_tags.add("pm:pacman")
        new_tags.add("dist:arch")

    if platforms.get("debian") or platforms.get("ubuntu"):
        new_tags.add("pm:apt")
        if platforms.get("debian"):
            new_tags.add("dist:debian")
        if platforms.get("ubuntu"):
            new_tags.add("dist:ubuntu")

    if platforms.get("fedora"):
        new_tags.add("pm:dnf")
        new_tags.add("dist:fedora")

    if platforms.get("flatpak"):
        new_tags.add("pm:flatpak")

    # Add PM tags based on existing package fields (especially important for packages without cache data)
    if package_data.get("arch-pkg"):
        new_tags.add("pm:pacman")
        new_tags.add("dist:arch")
        new_tags.add("os:linux")

    if package_data.get("apt-pkg"):
        new_tags.add("pm:apt")
        new_tags.add("dist:debian")
        new_tags.add("dist:ubuntu")
        new_tags.add("os:linux")

    if package_data.get("fedora-pkg"):
        new_tags.add("pm:dnf")
        new_tags.add("dist:fedora")
        new_tags.add("os:linux")

    if package_data.get("flatpak-pkg"):
        new_tags.add("pm:flatpak")
        # Flatpak can run on multiple OSes, but primarily Linux
        new_tags.add("os:linux")

    # For packages without cache data, try to infer from other clues
    if not has_cache_data:
        # If it has a brew-tap, it's likely a Homebrew package
        if package_data.get("brew-tap"):
            new_tags.add("pm:homebrew")
            new_tags.add("os:macos")  # Most homebrew packages support macOS

        # Check custom install patterns
        custom_install = package_data.get("custom-install", "")
        if "brew install" in custom_install or "brew cask install" in custom_install:
            if "cask" in custom_install:
                new_tags.add("pm:homebrew:cask")
                new_tags.add("os:macos")
            else:
                new_tags.add("pm:homebrew")
                new_tags.add("os:macos")

        if "flatpak install" in custom_install:
            new_tags.add("pm:flatpak")
            new_tags.add("os:linux")

        # Heuristics based on package names (for known cask patterns)
        cask_indicators = [
            "visual-studio-code",
            "claude",
            "ghostty",
            "kitty",
            "signal",
            "zoom",
            "zen",
            "dolphin",
            "parsec",
            "pinta",
        ]

        if package_name in cask_indicators or package_name.endswith("-cask"):
            new_tags.add("pm:homebrew:cask")
            new_tags.add("os:macos")

        # Flatpak app identifiers (com.*, org.*, etc.)
        if "." in package_name and (
            package_name.startswith("com.")
            or package_name.startswith("org.")
            or package_name.startswith("app.")
        ):
            new_tags.add("pm:flatpak")
            new_tags.add("os:linux")

        # Font packages (usually cross-platform)
        if (
            "font" in package_name.lower()
            or package_name.startswith("ttf-")
            or package_name.startswith("fonts-")
        ):
            new_tags.add("os:linux")
            new_tags.add("os:macos")
            # Could be multiple package managers

        # Tap packages (Homebrew specific)
        if package_name.endswith("-tap") or "tap" in package_name:
            new_tags.add("pm:homebrew")
            new_tags.add("os:macos")

    # Return only new tags (not already present)
    truly_new_tags = new_tags - current_tags
    return list(current_tags | new_tags), list(truly_new_tags)


def enhance_all_packages(toml_data, cache_data, dry_run=True):
    """Enhance tags for all packages."""
    enhancements = {}
    stats = {
        "total_packages": len(toml_data),
        "packages_enhanced": 0,
        "total_tags_added": 0,
        "casks_identified": 0,
        "os_tags_added": 0,
        "pm_tags_added": 0,
    }

    for package_name, package_data in toml_data.items():
        enhanced_tags, new_tags = enhance_package_tags(package_name, package_data, cache_data)

        if new_tags:
            stats["packages_enhanced"] += 1
            stats["total_tags_added"] += len(new_tags)

            # Count specific tag types
            for tag in new_tags:
                if tag.startswith("os:"):
                    stats["os_tags_added"] += 1
                elif tag.startswith("pm:"):
                    stats["pm_tags_added"] += 1
                    if tag == "pm:homebrew:cask":
                        stats["casks_identified"] += 1

            enhancements[package_name] = {
                "old_tags": package_data.get("tags", []),
                "new_tags": enhanced_tags,
                "added_tags": new_tags,
            }

            if not dry_run:
                # Apply the enhancement
                toml_data[package_name]["tags"] = enhanced_tags

    return enhancements, stats


def print_enhancement_report(enhancements, stats):
    """Print detailed enhancement report."""
    print("=== Package Tag Enhancement Report ===\n")

    print("📊 **Enhancement Statistics:**")
    print(f"   Total packages: {stats['total_packages']}")
    print(f"   Packages enhanced: {stats['packages_enhanced']}")
    print(f"   Total tags added: {stats['total_tags_added']}")
    print(f"   OS tags added: {stats['os_tags_added']}")
    print(f"   PM tags added: {stats['pm_tags_added']}")
    print(f"   Casks identified: {stats['casks_identified']}")
    print()

    print("🏷️ **Sample Enhancements:**")
    count = 0
    for package_name, enhancement in enhancements.items():
        if count >= 10:
            break
        print(f"   {package_name}:")
        print(f"      Added: {', '.join(enhancement['added_tags'])}")
        count += 1

    if len(enhancements) > 10:
        print(f"   ... and {len(enhancements) - 10} more packages enhanced")
    print()

    # Show cask enhancements specifically
    cask_enhancements = {
        k: v for k, v in enhancements.items() if "pm:homebrew:cask" in v["added_tags"]
    }

    if cask_enhancements:
        print("🍺 **Cask Enhancements:**")
        for package_name, enhancement in cask_enhancements.items():
            print(f"   {package_name}: {', '.join(enhancement['added_tags'])}")
        print()


def save_enhanced_toml(toml_data, output_path):
    """Save the enhanced TOML data."""
    with open(output_path, "w") as f:
        toml.dump(toml_data, f)
    print(f"✅ Enhanced TOML saved to {output_path}")


def main():
    """Main enhancement function."""
    import argparse

    parser = argparse.ArgumentParser(description="Enhance package tags based on cache data")
    parser.add_argument(
        "--dry-run", action="store_true", help="Preview changes without applying them"
    )
    parser.add_argument(
        "--output",
        default="packages/package_mappings.toml.enhanced",
        help="Output file for enhanced TOML",
    )

    args = parser.parse_args()

    print("Loading package data...")
    toml_data, cache_data = load_data()

    print("Enhancing package tags...")
    enhancements, stats = enhance_all_packages(toml_data, cache_data, dry_run=args.dry_run)

    print_enhancement_report(enhancements, stats)

    if not args.dry_run:
        save_enhanced_toml(toml_data, args.output)
        print(f"\n🎯 Apply changes with: mv {args.output} packages/package_mappings.toml")
    else:
        print("\n🔍 This was a dry run. Use --output to save changes.")
        print(f"    Run: uv run bin/enhance_package_tags.py --output {args.output}")


if __name__ == "__main__":
    main()
