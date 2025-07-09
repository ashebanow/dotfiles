#!/usr/bin/env python3
"""
Analyze current package tagging coverage and identify gaps.
"""

import json
import sys
from collections import Counter
from pathlib import Path

import toml


def load_toml_and_cache():
    """Load the TOML package mappings and Repology cache."""
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


def analyze_tagging_coverage(toml_data, cache_data):
    """Analyze current tagging coverage."""
    stats = {
        "total_packages": len(toml_data),
        "with_tags": 0,
        "with_os_tags": 0,
        "with_pm_tags": 0,
        "with_cask_potential": 0,
        "missing_basic_tags": [],
        "tag_distribution": Counter(),
        "cask_candidates": [],
        "platform_gaps": [],
    }

    for package_name, package_data in toml_data.items():
        tags = package_data.get("tags", [])

        if tags:
            stats["with_tags"] += 1
            for tag in tags:
                stats["tag_distribution"][tag] += 1

        # Check for OS tags
        os_tags = [tag for tag in tags if tag.startswith("os:")]
        if os_tags:
            stats["with_os_tags"] += 1

        # Check for PM tags
        pm_tags = [tag for tag in tags if tag.startswith("pm:")]
        if pm_tags:
            stats["with_pm_tags"] += 1

        # Check if package could be a cask (has cache entry with brew-is-cask)
        if package_name in cache_data:
            cache_entry = cache_data[package_name]
            if cache_entry.get("brew-is-cask", False):
                stats["with_cask_potential"] += 1
                stats["cask_candidates"].append(package_name)

        # Identify packages missing basic tags
        if not os_tags or not pm_tags:
            gaps = []
            if not os_tags:
                gaps.append("os:*")
            if not pm_tags:
                gaps.append("pm:*")

            stats["missing_basic_tags"].append(
                {"package": package_name, "missing": gaps, "current_tags": tags}
            )

        # Check for platform detection gaps
        has_platform_pkg = any(
            [
                package_data.get("arch-pkg"),
                package_data.get("apt-pkg"),
                package_data.get("fedora-pkg"),
                package_data.get("flatpak-pkg"),
            ]
        )

        if has_platform_pkg and not pm_tags:
            stats["platform_gaps"].append(
                {"package": package_name, "has_pkg_fields": True, "has_pm_tags": False}
            )

    return stats


def print_analysis(stats):
    """Print detailed analysis report."""
    print("=== Package Tagging Coverage Analysis ===\n")

    print("📊 **Overall Statistics:**")
    print(f"   Total packages: {stats['total_packages']}")
    print(
        f"   With any tags: {stats['with_tags']} ({stats['with_tags']/stats['total_packages']*100:.1f}%)"
    )
    print(
        f"   With OS tags: {stats['with_os_tags']} ({stats['with_os_tags']/stats['total_packages']*100:.1f}%)"
    )
    print(
        f"   With PM tags: {stats['with_pm_tags']} ({stats['with_pm_tags']/stats['total_packages']*100:.1f}%)"
    )
    print(f"   Cask candidates: {stats['with_cask_potential']}")
    print()

    print("🏷️ **Most Common Tags:**")
    for tag, count in stats["tag_distribution"].most_common(10):
        print(f"   {tag}: {count}")
    print()

    print("🍺 **Cask Candidates (from cache analysis):**")
    for package in stats["cask_candidates"]:
        print(f"   {package}")
    print()

    print(f"❌ **Packages Missing Basic Tags ({len(stats['missing_basic_tags'])}):**")
    for entry in stats["missing_basic_tags"][:10]:  # Show first 10
        print(f"   {entry['package']}: missing {', '.join(entry['missing'])}")
    if len(stats["missing_basic_tags"]) > 10:
        print(f"   ... and {len(stats['missing_basic_tags']) - 10} more")
    print()

    print(f"🔍 **Platform Detection Gaps ({len(stats['platform_gaps'])}):**")
    for entry in stats["platform_gaps"][:5]:  # Show first 5
        print(f"   {entry['package']}: has package fields but no pm: tags")
    if len(stats["platform_gaps"]) > 5:
        print(f"   ... and {len(stats['platform_gaps']) - 5} more")


def suggest_enhancements(toml_data, cache_data):
    """Suggest specific tag enhancements."""
    print("\n=== Enhancement Suggestions ===\n")

    suggestions = []

    for package_name, package_data in toml_data.items():
        tags = set(package_data.get("tags", []))
        suggested_tags = set()

        # Suggest OS tags based on cache data
        if package_name in cache_data:
            cache_entry = cache_data[package_name]
            platforms = cache_entry.get("platforms", {})

            if platforms.get("homebrew") or cache_entry.get("brew-supports-darwin"):
                suggested_tags.add("os:macos")

            if (
                platforms.get("arch_official")
                or platforms.get("arch_aur")
                or platforms.get("debian")
                or platforms.get("ubuntu")
                or platforms.get("fedora")
            ):
                suggested_tags.add("os:linux")

            # Suggest PM tags
            if cache_entry.get("brew-is-cask", False):
                suggested_tags.add("pm:homebrew:cask")
            elif platforms.get("homebrew"):
                suggested_tags.add("pm:homebrew")

            if platforms.get("arch_official") or platforms.get("arch_aur"):
                suggested_tags.add("pm:pacman")

            if platforms.get("debian") or platforms.get("ubuntu"):
                suggested_tags.add("pm:apt")

            if platforms.get("fedora"):
                suggested_tags.add("pm:dnf")

            if platforms.get("flatpak"):
                suggested_tags.add("pm:flatpak")

        # Suggest PM tags based on existing package fields
        if package_data.get("arch-pkg"):
            suggested_tags.add("pm:pacman")
            suggested_tags.add("os:linux")

        if package_data.get("apt-pkg"):
            suggested_tags.add("pm:apt")
            suggested_tags.add("os:linux")

        if package_data.get("fedora-pkg"):
            suggested_tags.add("pm:dnf")
            suggested_tags.add("os:linux")

        if package_data.get("flatpak-pkg"):
            suggested_tags.add("pm:flatpak")

        # Find new suggestions
        new_tags = suggested_tags - tags
        if new_tags:
            suggestions.append(
                {
                    "package": package_name,
                    "current_tags": list(tags),
                    "suggested_new_tags": list(new_tags),
                }
            )

    print(f"💡 **Tag Enhancement Suggestions ({len(suggestions)} packages):**")
    for suggestion in suggestions[:10]:  # Show first 10
        print(f"   {suggestion['package']}:")
        print(f"      Add: {', '.join(suggestion['suggested_new_tags'])}")

    if len(suggestions) > 10:
        print(f"   ... and {len(suggestions) - 10} more packages need tag enhancements")

    return suggestions


def main():
    """Main analysis function."""
    print("Loading package data...")
    toml_data, cache_data = load_toml_and_cache()

    print("Analyzing tagging coverage...")
    stats = analyze_tagging_coverage(toml_data, cache_data)

    print_analysis(stats)
    suggestions = suggest_enhancements(toml_data, cache_data)

    print("\n=== Summary ===")
    print(f"📈 Tagging coverage: {stats['with_tags']}/{stats['total_packages']} packages have tags")
    print(f"🎯 Enhancement potential: {len(suggestions)} packages could get additional tags")
    print(f"🍺 Cask support needed: {stats['with_cask_potential']} packages are casks")

    return stats, suggestions


if __name__ == "__main__":
    main()
