#!/usr/bin/env -S uv run --script
"""
Format package_mappings.toml to have a maximum of 4 tags per line.
Improves readability by breaking long tag arrays into multiple lines.
"""
# /// script
# dependencies = [
#   "toml",
# ]
# ///

import argparse
import re
import sys
from pathlib import Path

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
except ImportError:
    print("Error: toml library required for writing. Install with: pip install toml")
    sys.exit(1)


def sort_tags_by_prefix(tags):
    """Sort tags alphabetically while keeping prefix groups together."""
    if not tags:
        return []
    
    # Group tags by prefix (everything before first colon)
    prefix_groups = {}
    no_prefix = []
    
    for tag in tags:
        if ':' in tag:
            prefix = tag.split(':', 1)[0]
            if prefix not in prefix_groups:
                prefix_groups[prefix] = []
            prefix_groups[prefix].append(tag)
        else:
            no_prefix.append(tag)
    
    # Sort within each prefix group
    for prefix in prefix_groups:
        prefix_groups[prefix].sort()
    
    # Sort tags without prefixes
    no_prefix.sort()
    
    # Combine: sorted prefixes, then their tags, then no-prefix tags
    result = []
    for prefix in sorted(prefix_groups.keys()):
        result.extend(prefix_groups[prefix])
    result.extend(no_prefix)
    
    return result


def format_tags_array(tags, max_per_line=4, indent=""):
    """Format a tags array with max_per_line tags per line."""
    if not tags:
        return "[]"
    
    # Sort tags by prefix groups
    sorted_tags = sort_tags_by_prefix(tags)
    
    if len(sorted_tags) <= max_per_line:
        # Single line if it fits
        formatted_tags = ", ".join(f'"{tag}"' for tag in sorted_tags)
        return f'[ {formatted_tags},]'
    
    # Multi-line format
    lines = ["["]
    
    for i in range(0, len(sorted_tags), max_per_line):
        chunk = sorted_tags[i:i + max_per_line]
        formatted_chunk = ", ".join(f'"{tag}"' for tag in chunk)
        lines.append(f'  {formatted_chunk},')
    
    lines.append("]")
    
    return "\n".join(lines)


def format_toml_content(toml_data, max_tags_per_line=4):
    """Format TOML content with custom tag formatting."""
    lines = []
    
    for package_name in sorted(toml_data.keys()):
        entry = toml_data[package_name]
        
        # Add package header
        lines.append(f"[{package_name}]")
        
        # Add description if present
        if 'description' in entry:
            description = entry['description'].replace('"', '\\"')
            lines.append(f'description = "{description}"')
        
        # Format tags with custom line breaking
        if 'tags' in entry:
            tags = entry['tags']
            formatted_tags = format_tags_array(tags, max_tags_per_line)
            if '\n' in formatted_tags:
                # Multi-line tags
                lines.append(f"tags = {formatted_tags}")
            else:
                # Single line tags
                lines.append(f"tags = {formatted_tags}")
        
        # Add other fields (alphabetically, excluding description and tags)
        other_fields = {k: v for k, v in entry.items() if k not in ['description', 'tags']}
        for key in sorted(other_fields.keys()):
            value = other_fields[key]
            if isinstance(value, str):
                if value == "":
                    lines.append(f'{key} = ""')
                else:
                    escaped_value = value.replace('"', '\\"')
                    lines.append(f'{key} = "{escaped_value}"')
            else:
                lines.append(f'{key} = {value}')
        
        # Add blank line between packages
        lines.append("")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description='Format package_mappings.toml with readable tag formatting'
    )
    
    parser.add_argument('--toml', '-t', 
                       help='Path to package_mappings.toml file')
    parser.add_argument('--output', '-o',
                       help='Output file path (default: overwrite input)')
    parser.add_argument('--max-tags-per-line', type=int, default=4,
                       help='Maximum tags per line (default: 4)')
    parser.add_argument('--dry-run', action='store_true',
                       help='Preview changes without writing')
    
    args = parser.parse_args()
    
    # Set default TOML path
    if not args.toml:
        default_toml = Path("packages/package_mappings.toml")
        if default_toml.exists():
            args.toml = str(default_toml)
        else:
            print(f"Error: No TOML file found at {default_toml}")
            sys.exit(1)
    
    print(f"=== TOML Tag Formatting ===")
    print(f"Input: {args.toml}")
    print(f"Max tags per line: {args.max_tags_per_line}")
    print(f"Mode: {'DRY RUN' if args.dry_run else 'APPLY CHANGES'}")
    
    try:
        # Load TOML data
        toml_data = load_toml(args.toml)
        print(f"Loaded {len(toml_data)} packages")
        
        # Format the content
        formatted_content = format_toml_content(toml_data, args.max_tags_per_line)
        
        if args.dry_run:
            print("\n=== PREVIEW (first 50 lines) ===")
            preview_lines = formatted_content.split('\n')[:50]
            for i, line in enumerate(preview_lines, 1):
                print(f"{i:3d}: {line}")
            if len(formatted_content.split('\n')) > 50:
                print(f"... and {len(formatted_content.split('\n')) - 50} more lines")
            print(f"\nRun without --dry-run to apply formatting")
        else:
            # Write formatted content
            output_file = args.output or args.toml
            with open(output_file, 'w') as f:
                f.write(formatted_content)
            
            print(f"✓ Formatted TOML written to: {output_file}")
            
            # Show some stats
            original_lines = Path(args.toml).read_text().count('\n')
            new_lines = formatted_content.count('\n')
            print(f"✓ Lines: {original_lines} → {new_lines}")
            
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()