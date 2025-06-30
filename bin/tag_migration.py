#!/usr/bin/env python3
"""
Tag Migration Utility - Migrate package entries from legacy format to tagged format

This script helps migrate existing package_mappings.toml entries to use the new
tagging system while preserving backward compatibility.
"""

import argparse
import sys
from pathlib import Path
from typing import Any, Dict, List

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.tagged_package_filter import auto_categorize_package, migrate_package_to_tags

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


def write_toml(data: Dict[str, Any], filepath: str) -> None:
    """Write TOML data with proper formatting."""
    with open(filepath, "w") as f:
        for package_name in sorted(data.keys()):
            entry = data[package_name]

            # Section header
            if "." in package_name or "@" in package_name:
                f.write(f'["{package_name}"]\n')
            else:
                f.write(f"[{package_name}]\n")

            # Write fields in consistent order
            field_order = [
                "description",
                "tags",  # Important fields first
                "arch-pkg",
                "arch-is-aur",
                "apt-pkg",
                "fedora-pkg",
                "flatpak-pkg",  # Package managers
                "brew-pkg",
                "brew-tap",
                "brew-supports-darwin",
                "brew-supports-linux",
                "brew-is-cask",  # Homebrew
                "prefer_flatpak",
                "priority",
                "custom-install-priority",  # Priorities
                "custom-install",
                "requires-confirmation",
                "install-condition",  # Custom install
            ]

            # First pass: write ordered fields
            written_keys = set()
            for key in field_order:
                if key in entry:
                    write_field(f, key, entry[key])
                    written_keys.add(key)

            # Second pass: write any remaining fields
            for key, value in sorted(entry.items()):
                if key not in written_keys and key != "custom-install":
                    write_field(f, key, value)

            # Handle hierarchical custom-install
            if "custom-install" in entry and isinstance(entry["custom-install"], dict):
                f.write(f"\n[{package_name}.custom-install]\n")
                for platform, commands in sorted(entry["custom-install"].items()):
                    if isinstance(commands, list):
                        f.write(f"{platform} = [\n")
                        for cmd in commands:
                            f.write(f'  "{cmd}",\n')
                        f.write("]\n")
                    else:
                        f.write(f'{platform} = "{commands}"\n')

            f.write("\n")


def write_field(f, key: str, value: Any) -> None:
    """Write a single TOML field with proper formatting."""
    if isinstance(value, str):
        # Escape quotes in strings
        escaped_value = value.replace("\\", "\\\\").replace('"', '\\"')
        f.write(f'{key} = "{escaped_value}"\n')
    elif isinstance(value, bool):
        f.write(f"{key} = {str(value).lower()}\n")
    elif isinstance(value, list):
        if not value:
            f.write(f"{key} = []\n")
        else:
            f.write(f"{key} = [\n")
            for item in value:
                if isinstance(item, str):
                    escaped_item = item.replace("\\", "\\\\").replace('"', '\\"')
                    f.write(f'  "{escaped_item}",\n')
                else:
                    f.write(f"  {item},\n")
            f.write("]\n")
    elif value is None:
        f.write(f'{key} = ""\n')
    else:
        f.write(f"{key} = {value}\n")


def analyze_migration(toml_data: Dict[str, Any]) -> Dict[str, Any]:
    """Analyze the current state of migration in the TOML data."""
    stats = {
        "total_packages": len(toml_data),
        "migrated": 0,
        "legacy": 0,
        "partially_migrated": 0,
        "tag_distribution": {},
        "legacy_fields_usage": {},
    }

    legacy_fields = [
        "brew-supports-darwin",
        "brew-supports-linux",
        "brew-is-cask",
        "arch-is-aur",
        "prefer_flatpak",
    ]

    for package_name, entry in toml_data.items():
        has_tags = "tags" in entry and entry["tags"]
        has_legacy = any(field in entry for field in legacy_fields)

        if has_tags and not has_legacy:
            stats["migrated"] += 1
        elif not has_tags and has_legacy:
            stats["legacy"] += 1
        elif has_tags and has_legacy:
            stats["partially_migrated"] += 1

        # Count tag usage
        if has_tags:
            for tag in entry["tags"]:
                stats["tag_distribution"][tag] = stats["tag_distribution"].get(tag, 0) + 1

        # Count legacy field usage
        for field in legacy_fields:
            if field in entry:
                stats["legacy_fields_usage"][field] = stats["legacy_fields_usage"].get(field, 0) + 1

    return stats


def migrate_packages(
    toml_data: Dict[str, Any],
    packages: List[str] = None,
    auto_categorize: bool = True,
    preserve_legacy: bool = True,
) -> Dict[str, Any]:
    """Migrate packages to tagged format."""
    migrated_data = {}

    for package_name, entry in toml_data.items():
        # Skip if specific packages requested and this isn't one
        if packages and package_name not in packages:
            migrated_data[package_name] = entry.copy()
            continue

        # Skip if already fully migrated
        if "tags" in entry and not preserve_legacy:
            # Remove legacy fields if not preserving
            migrated_entry = entry.copy()
            legacy_fields = [
                "brew-supports-darwin",
                "brew-supports-linux",
                "brew-is-cask",
                "arch-is-aur",
                "prefer_flatpak",
            ]
            for field in legacy_fields:
                migrated_entry.pop(field, None)
            migrated_data[package_name] = migrated_entry
            continue

        # Migrate the package
        migrated_entry = migrate_package_to_tags(entry)

        # Auto-categorize if requested
        if auto_categorize:
            description = entry.get("description", "")
            if description and not description.startswith("TODO:"):
                suggested_tags = auto_categorize_package(package_name, description)

                # Add suggested tags that aren't already present
                existing_tags = set(migrated_entry.get("tags", []))
                for tag in suggested_tags:
                    if tag not in existing_tags:
                        migrated_entry["tags"].append(tag)

        # Remove legacy fields if not preserving
        if not preserve_legacy:
            legacy_fields = [
                "brew-supports-darwin",
                "brew-supports-linux",
                "brew-is-cask",
                "arch-is-aur",
                "prefer_flatpak",
            ]
            for field in legacy_fields:
                migrated_entry.pop(field, None)

        migrated_data[package_name] = migrated_entry

    return migrated_data


def add_role_tags(toml_data: Dict[str, Any], role_mapping: Dict[str, List[str]]) -> Dict[str, Any]:
    """Add role tags based on package names and categories."""
    default_role_mapping = {
        "development": [
            "git",
            "gcc",
            "clang",
            "python",
            "node",
            "rust",
            "go",
            "java",
            "vim",
            "neovim",
            "emacs",
            "vscode",
            "intellij",
            "sublime",
            "docker",
            "vagrant",
            "virtualbox",
            "gdb",
            "lldb",
            "valgrind",
        ],
        "server": [
            "nginx",
            "apache",
            "postgresql",
            "mysql",
            "redis",
            "memcached",
            "prometheus",
            "grafana",
            "elasticsearch",
            "logstash",
            "kibana",
        ],
        "desktop": [
            "firefox",
            "chrome",
            "slack",
            "discord",
            "zoom",
            "spotify",
            "vlc",
            "gimp",
            "inkscape",
            "libreoffice",
            "thunderbird",
        ],
        "security": [
            "gpg",
            "pass",
            "keepass",
            "bitwarden",
            "openssl",
            "openssh",
            "fail2ban",
            "ufw",
            "iptables",
            "nmap",
            "wireshark",
        ],
        "data-science": [
            "jupyter",
            "anaconda",
            "pandas",
            "numpy",
            "scikit-learn",
            "tensorflow",
            "pytorch",
            "r",
            "octave",
            "matlab",
        ],
    }

    # Merge with provided mapping
    role_mapping = {**default_role_mapping, **role_mapping}

    updated_data = {}
    for package_name, entry in toml_data.items():
        updated_entry = entry.copy()

        # Ensure tags field exists
        if "tags" not in updated_entry:
            updated_entry["tags"] = []

        existing_tags = set(updated_entry["tags"])

        # Check each role
        for role, patterns in role_mapping.items():
            for pattern in patterns:
                if pattern in package_name.lower():
                    role_tag = f"role:{role}"
                    if role_tag not in existing_tags:
                        updated_entry["tags"].append(role_tag)
                        existing_tags.add(role_tag)

        updated_data[package_name] = updated_entry

    return updated_data


def main():
    parser = argparse.ArgumentParser(
        description="Migrate package entries to use the tagging system"
    )
    parser.add_argument("toml_file", help="Path to package_mappings.toml file")
    parser.add_argument(
        "-o", "--output", help="Output file (default: overwrite input file)", default=None
    )
    parser.add_argument("--packages", nargs="+", help="Specific packages to migrate (default: all)")
    parser.add_argument(
        "--no-auto-categorize",
        action="store_true",
        help="Disable automatic category tag suggestions",
    )
    parser.add_argument(
        "--remove-legacy", action="store_true", help="Remove legacy fields after migration"
    )
    parser.add_argument(
        "--add-roles", action="store_true", help="Add role tags based on package names"
    )
    parser.add_argument(
        "--analyze", action="store_true", help="Analyze migration status without making changes"
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="Show what would be changed without writing"
    )

    args = parser.parse_args()

    # Load TOML data
    toml_data = load_toml(args.toml_file)
    if not toml_data:
        return 1

    # Analyze mode
    if args.analyze:
        stats = analyze_migration(toml_data)
        print("\n=== Migration Analysis ===")
        print(f"Total packages: {stats['total_packages']}")
        print(f"Fully migrated: {stats['migrated']}")
        print(f"Legacy format: {stats['legacy']}")
        print(f"Partially migrated: {stats['partially_migrated']}")

        if stats["tag_distribution"]:
            print("\n=== Tag Distribution ===")
            for tag, count in sorted(
                stats["tag_distribution"].items(), key=lambda x: x[1], reverse=True
            )[:20]:
                print(f"{tag}: {count}")

        if stats["legacy_fields_usage"]:
            print("\n=== Legacy Field Usage ===")
            for field, count in sorted(stats["legacy_fields_usage"].items()):
                print(f"{field}: {count}")

        return 0

    # Migrate packages
    migrated_data = migrate_packages(
        toml_data,
        packages=args.packages,
        auto_categorize=not args.no_auto_categorize,
        preserve_legacy=not args.remove_legacy,
    )

    # Add role tags if requested
    if args.add_roles:
        migrated_data = add_role_tags(migrated_data, {})

    # Dry run mode
    if args.dry_run:
        print("\n=== Migration Preview ===")
        changed_count = 0

        for package_name in sorted(migrated_data.keys()):
            original = toml_data.get(package_name, {})
            migrated = migrated_data[package_name]

            if original != migrated:
                changed_count += 1
                print(f"\n{package_name}:")

                # Show tag changes
                original_tags = set(original.get("tags", []))
                migrated_tags = set(migrated.get("tags", []))

                added_tags = migrated_tags - original_tags
                if added_tags:
                    print(f"  + Tags: {', '.join(sorted(added_tags))}")

                # Show removed fields
                if args.remove_legacy:
                    removed_fields = set(original.keys()) - set(migrated.keys())
                    if removed_fields:
                        print(f"  - Fields: {', '.join(sorted(removed_fields))}")

        print(f"\nTotal packages to be modified: {changed_count}")
        return 0

    # Write output
    output_file = args.output or args.toml_file
    write_toml(migrated_data, output_file)

    # Report results
    stats_before = analyze_migration(toml_data)
    stats_after = analyze_migration(migrated_data)

    print("\n✅ Migration complete!")
    print(f"Migrated packages: {stats_after['migrated'] - stats_before['migrated']}")
    print(f"Output written to: {output_file}")

    if stats_after["legacy"] > 0:
        print(f"\n⚠️  {stats_after['legacy']} packages still in legacy format")
        print("Run with --analyze to see details")

    return 0


if __name__ == "__main__":
    sys.exit(main())
