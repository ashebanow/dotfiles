#!/usr/bin/env python3
"""Reformat package_mappings.toml to have alphabetized tags with one tag per line"""

import toml

def format_tags(tags):
    """Format a list of tags with one tag per line, alphabetized"""
    if not tags:
        return "[]"
    
    # Remove duplicates and sort tags alphabetically
    sorted_tags = sorted(set(tags))
    
    if len(sorted_tags) == 1:
        # Single tag on one line
        return f'["{sorted_tags[0]}"]'
    else:
        # Multiple lines with one tag per line
        lines = ["["]
        for i, tag in enumerate(sorted_tags):
            if i < len(sorted_tags) - 1:
                lines.append(f'    "{tag}",')
            else:
                lines.append(f'    "{tag}"')
        lines.append("]")
        return "\n".join(lines)

def main():
    # Load TOML
    print("Loading package_mappings.toml...")
    with open("packages/package_mappings.toml") as f:
        toml_data = toml.load(f)
    
    # Write formatted TOML
    print("Writing reformatted TOML...")
    with open("packages/package_mappings.toml", "w") as f:
        for package_name in sorted(toml_data.keys()):
            entry = toml_data[package_name]
            
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
                formatted_tags = format_tags(entry["tags"])
                if "\n" in formatted_tags:
                    f.write(f"tags = {formatted_tags}\n")
                else:
                    f.write(f"tags = {formatted_tags}\n")
            
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
    
    print("Done! Tags are now alphabetized with one tag per line.")

if __name__ == "__main__":
    main()