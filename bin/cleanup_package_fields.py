#!/usr/bin/env -S uv run --script
"""
Clean up redundant package fields from package_mappings.toml.

This tool removes:
1. Empty string fields that have fallback behavior
2. Package fields that match the canonical name (TOML key)
3. Empty priority and brew-tap fields

Preserves:
- Flatpak fields (no fallback behavior)
- Fields with different names than canonical
- Non-empty priority/brew-tap fields
"""
# /// script
# dependencies = [
#   "toml",
# ]
# ///

import argparse
import sys
from pathlib import Path
from typing import Dict, Any, Set

# Try to import TOML parser
try:
    import tomllib  # Python 3.11+
    def load_toml(filepath):
        with open(filepath, 'rb') as f:
            return tomllib.load(f)
except ImportError:
    try:
        import toml
        def load_toml(filepath):
            with open(filepath, 'r') as f:
                return toml.load(f)
    except ImportError:
        def load_toml(filepath):
            raise ImportError("No TOML library available. Install with: pip install toml")

try:
    import toml as toml_writer
    def dump_toml(data, filepath):
        with open(filepath, 'w') as f:
            toml_writer.dump(data, f)
except ImportError:
    def dump_toml(data, filepath):
        raise ImportError("toml library required for writing. Install with: pip install toml")


def analyze_cleanup_opportunities(toml_data: Dict[str, Dict[str, Any]]) -> Dict[str, Any]:
    """Analyze what can be safely cleaned up."""
    stats = {
        'total_packages': len(toml_data),
        'empty_fields_found': 0,
        'canonical_matches_found': 0,
        'cleanable_packages': set(),
        'changes_by_package': {},
        'fields_with_fallbacks': ['arch-pkg', 'apt-pkg', 'fedora-pkg', 'brew-pkg'],
        'always_cleanable': ['brew-tap', 'priority'],  # These can always be cleaned if empty
    }
    
    for package_name, entry in toml_data.items():
        changes = []
        
        # Check for empty fields that can be removed
        for field in ['arch-pkg', 'apt-pkg', 'fedora-pkg', 'flatpak-pkg', 'brew-tap', 'priority']:
            value = entry.get(field, '')
            if value == '':
                changes.append(f"Remove empty {field}")
                stats['empty_fields_found'] += 1
        
        # Check for fields that match canonical name (except flatpak - no fallback)
        for field in ['arch-pkg', 'apt-pkg', 'fedora-pkg']:
            value = entry.get(field, '')
            if value == package_name:
                changes.append(f"Remove {field} (matches canonical name '{package_name}')")
                stats['canonical_matches_found'] += 1
        
        # Check brew-pkg separately since it's only present in some entries
        brew_pkg = entry.get('brew-pkg')
        if brew_pkg == package_name:
            changes.append(f"Remove brew-pkg (matches canonical name '{package_name}')")
            stats['canonical_matches_found'] += 1
        
        if changes:
            stats['cleanable_packages'].add(package_name)
            stats['changes_by_package'][package_name] = changes
    
    return stats


def clean_package_entry(package_name: str, entry: Dict[str, Any]) -> Dict[str, Any]:
    """Clean up a single package entry, returning a new cleaned dict."""
    cleaned = entry.copy()
    
    # Remove empty fields that have fallback behavior or are always cleanable
    cleanable_if_empty = ['arch-pkg', 'apt-pkg', 'fedora-pkg', 'flatpak-pkg', 'brew-tap', 'priority']
    for field in cleanable_if_empty:
        if field in cleaned and cleaned[field] == '':
            del cleaned[field]
    
    # Remove fields that match canonical name (except flatpak)
    fallback_fields = ['arch-pkg', 'apt-pkg', 'fedora-pkg']
    for field in fallback_fields:
        if field in cleaned and cleaned[field] == package_name:
            del cleaned[field]
    
    # Check brew-pkg separately
    if 'brew-pkg' in cleaned and cleaned['brew-pkg'] == package_name:
        del cleaned['brew-pkg']
    
    return cleaned


def cleanup_toml_file(toml_path: str, output_path: str = None, dry_run: bool = True) -> Dict[str, Any]:
    """Clean up the TOML file."""
    
    # Load original data
    toml_data = load_toml(toml_path)
    print(f"Loaded {len(toml_data)} packages from {toml_path}")
    
    # Analyze cleanup opportunities
    print("\n=== CLEANUP ANALYSIS ===")
    stats = analyze_cleanup_opportunities(toml_data)
    
    print(f"Total packages: {stats['total_packages']}")
    print(f"Empty fields found: {stats['empty_fields_found']}")
    print(f"Canonical name matches found: {stats['canonical_matches_found']}")
    print(f"Packages that can be cleaned: {len(stats['cleanable_packages'])}")
    
    if dry_run:
        print(f"\n=== DRY RUN - CHANGES PREVIEW ===")
        for package_name in sorted(stats['cleanable_packages'])[:10]:  # Show first 10
            print(f"\n{package_name}:")
            for change in stats['changes_by_package'][package_name]:
                print(f"  - {change}")
        
        if len(stats['cleanable_packages']) > 10:
            print(f"\n... and {len(stats['cleanable_packages']) - 10} more packages")
        
        print(f"\nRun with --apply to make these changes")
        return stats
    
    # Apply cleanup
    print(f"\n=== APPLYING CLEANUP ===")
    cleaned_data = {}
    changes_made = 0
    
    for package_name, entry in toml_data.items():
        original_size = len(entry)
        cleaned_entry = clean_package_entry(package_name, entry)
        cleaned_data[package_name] = cleaned_entry
        
        if len(cleaned_entry) < original_size:
            changes_made += 1
            removed_fields = original_size - len(cleaned_entry)
            print(f"  {package_name}: removed {removed_fields} field(s)")
    
    # Write cleaned data
    output_file = output_path or toml_path
    dump_toml(cleaned_data, output_file)
    print(f"\n✓ Cleaned TOML written to: {output_file}")
    print(f"✓ Modified {changes_made} packages")
    
    return stats


def main():
    parser = argparse.ArgumentParser(description='Clean up redundant package fields')
    
    parser.add_argument('--toml', '-t', 
                       help='Path to package_mappings.toml file')
    parser.add_argument('--output', '-o',
                       help='Output file path (default: overwrite input)')
    parser.add_argument('--apply', action='store_true',
                       help='Apply changes (default is dry-run)')
    
    args = parser.parse_args()
    
    # Set default TOML path
    if not args.toml:
        default_toml = Path("packages/package_mappings.toml")
        if default_toml.exists():
            args.toml = str(default_toml)
        else:
            print(f"Error: No TOML file found at {default_toml}")
            sys.exit(1)
    
    print(f"=== Package Field Cleanup ===")
    print(f"Input: {args.toml}")
    print(f"Mode: {'APPLY CHANGES' if args.apply else 'DRY RUN'}")
    
    try:
        stats = cleanup_toml_file(
            toml_path=args.toml,
            output_path=args.output,
            dry_run=not args.apply
        )
        
        if not args.apply:
            print(f"\n=== SUMMARY ===")
            print(f"Ready to remove {stats['empty_fields_found']} empty fields")
            print(f"Ready to remove {stats['canonical_matches_found']} redundant canonical name fields")
            print(f"This will clean up {len(stats['cleanable_packages'])} packages")
            
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()