#!/usr/bin/env -S uv run --script
"""
Clean up redundant tags in package_mappings.toml.

This tool removes:
1. Redundant pm:homebrew tags when both general and specific versions exist
2. Other hierarchical tag redundancies
3. Duplicate tags within the same package
"""
# /// script
# dependencies = [
#   "toml",
# ]
# ///

import argparse
import sys
from pathlib import Path
from typing import Any, Dict, List

# Try to import TOML parser
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


try:
    import toml as toml_writer

    def dump_toml(data, filepath):
        with open(filepath, "w") as f:
            toml_writer.dump(data, f)

except ImportError:

    def dump_toml(data, filepath):
        raise ImportError("toml library required for writing. Install with: pip install toml")


def analyze_tag_redundancies(tags: List[str]) -> Dict[str, Any]:
    """Analyze a list of tags for redundancies."""
    issues = {
        "duplicates": [],
        "homebrew_normalization": False,
        "pm_redundancies": [],
        "original_count": len(tags),
        "unique_tags": list(dict.fromkeys(tags)),  # Remove duplicates while preserving order
    }

    # Check for exact duplicates
    seen = set()
    for tag in tags:
        if tag in seen:
            issues["duplicates"].append(tag)
        seen.add(tag)

    # Check for pm:homebrew normalization opportunity
    has_general_homebrew = "pm:homebrew" in tags
    has_darwin_homebrew = "pm:homebrew:darwin" in tags
    has_linux_homebrew = "pm:homebrew:linux" in tags

    # If we have both platform-specific tags, we should normalize to general tag
    if has_darwin_homebrew and has_linux_homebrew:
        issues["homebrew_normalization"] = True
        issues["pm_redundancies"].append("Replace platform-specific tags with general pm:homebrew")

    return issues


def clean_tags(tags: List[str]) -> List[str]:
    """Clean up redundant tags."""
    # Remove exact duplicates while preserving order
    cleaned_tags = list(dict.fromkeys(tags))

    # Handle pm:homebrew redundancy/normalization
    has_general_homebrew = "pm:homebrew" in cleaned_tags
    has_darwin_homebrew = "pm:homebrew:darwin" in cleaned_tags
    has_linux_homebrew = "pm:homebrew:linux" in cleaned_tags

    # Normalize homebrew tags: if we have both platform-specific tags, use general tag instead
    if has_darwin_homebrew and has_linux_homebrew:
        # Remove platform-specific tags and ensure general tag is present
        if has_darwin_homebrew:
            cleaned_tags.remove("pm:homebrew:darwin")
        if has_linux_homebrew:
            cleaned_tags.remove("pm:homebrew:linux")
        if not has_general_homebrew:
            cleaned_tags.append("pm:homebrew")

    return cleaned_tags


def analyze_toml_redundancies(toml_data: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
    """Analyze all packages for tag redundancies."""
    stats = {
        "total_packages": len(toml_data),
        "packages_with_issues": 0,
        "total_duplicates": 0,
        "homebrew_redundancies": 0,
        "tags_saved": 0,
        "issues_by_package": {},
    }

    for package_name, entry in toml_data.items():
        tags = entry.get("tags", [])
        if not tags:
            continue

        issues = analyze_tag_redundancies(tags)

        if issues["duplicates"] or issues["homebrew_normalization"]:
            stats["packages_with_issues"] += 1
            stats["issues_by_package"][package_name] = issues

            stats["total_duplicates"] += len(issues["duplicates"])
            if issues["homebrew_normalization"]:
                stats["homebrew_redundancies"] += 1

            # Calculate potential tags saved
            cleaned_count = len(clean_tags(tags))
            stats["tags_saved"] += issues["original_count"] - cleaned_count

    return stats


def cleanup_toml_tags(
    toml_path: str, output_path: str = None, dry_run: bool = True
) -> Dict[str, Any]:
    """Clean up tag redundancies in the TOML file."""

    # Load original data
    toml_data = load_toml(toml_path)
    print(f"Loaded {len(toml_data)} packages from {toml_path}")

    # Analyze redundancies
    print("\n=== TAG REDUNDANCY ANALYSIS ===")
    stats = analyze_toml_redundancies(toml_data)

    print(f"Total packages: {stats['total_packages']}")
    print(f"Packages with tag issues: {stats['packages_with_issues']}")
    print(f"Total duplicate tags found: {stats['total_duplicates']}")
    print(f"Packages with pm:homebrew redundancy: {stats['homebrew_redundancies']}")
    print(f"Total tags that can be removed: {stats['tags_saved']}")

    if dry_run:
        print("\n=== DRY RUN - CHANGES PREVIEW ===")

        # Show examples of issues
        shown = 0
        for package_name, issues in stats["issues_by_package"].items():
            if shown >= 10:  # Limit to first 10 examples
                break

            print(f"\n{package_name}:")
            if issues["duplicates"]:
                print(f"  - Remove duplicate tags: {issues['duplicates']}")
            if issues["homebrew_normalization"]:
                print("  - Normalize to general pm:homebrew tag (replace platform-specific)")
            print(
                f"  - Tag count: {issues['original_count']} → {len(clean_tags(toml_data[package_name].get('tags', [])))}"
            )
            shown += 1

        if len(stats["issues_by_package"]) > 10:
            remaining = len(stats["issues_by_package"]) - 10
            print(f"\n... and {remaining} more packages with similar issues")

        print("\nRun with --apply to make these changes")
        return stats

    # Apply cleanup
    print("\n=== APPLYING TAG CLEANUP ===")
    cleaned_data = {}
    packages_modified = 0
    total_tags_removed = 0

    for package_name, entry in toml_data.items():
        cleaned_entry = entry.copy()
        original_tags = entry.get("tags", [])

        if original_tags:
            cleaned_tags = clean_tags(original_tags)

            if len(cleaned_tags) < len(original_tags):
                packages_modified += 1
                tags_removed = len(original_tags) - len(cleaned_tags)
                total_tags_removed += tags_removed
                print(f"  {package_name}: removed {tags_removed} redundant tag(s)")

            cleaned_entry["tags"] = cleaned_tags

        cleaned_data[package_name] = cleaned_entry

    # Write cleaned data
    output_file = output_path or toml_path
    dump_toml(cleaned_data, output_file)
    print(f"\n✓ Cleaned TOML written to: {output_file}")
    print(f"✓ Modified {packages_modified} packages")
    print(f"✓ Removed {total_tags_removed} redundant tags")

    return stats


def main():
    parser = argparse.ArgumentParser(description="Clean up redundant tags in package mappings")

    parser.add_argument("--toml", "-t", help="Path to package_mappings.toml file")
    parser.add_argument("--output", "-o", help="Output file path (default: overwrite input)")
    parser.add_argument("--apply", action="store_true", help="Apply changes (default is dry-run)")

    args = parser.parse_args()

    # Set default TOML path
    if not args.toml:
        default_toml = Path("packages/package_mappings.toml")
        if default_toml.exists():
            args.toml = str(default_toml)
        else:
            print(f"Error: No TOML file found at {default_toml}")
            sys.exit(1)

    print("=== Tag Redundancy Cleanup ===")
    print(f"Input: {args.toml}")
    print(f"Mode: {'APPLY CHANGES' if args.apply else 'DRY RUN'}")

    try:
        stats = cleanup_toml_tags(
            toml_path=args.toml, output_path=args.output, dry_run=not args.apply
        )

        if not args.apply:
            print("\n=== SUMMARY ===")
            print(f"Ready to remove {stats['tags_saved']} redundant tags")
            print(f"This will clean up {stats['packages_with_issues']} packages")
            print(
                f"Key redundancy: {stats['homebrew_redundancies']} packages have pm:homebrew redundancy"
            )

    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
