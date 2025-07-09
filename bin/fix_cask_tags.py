#!/usr/bin/env python3
"""Fix cask tags: remove pm:homebrew:cask, ensure cat:cask + os:macos + pm:homebrew:macos"""

import toml

# Load TOML
print("Loading package_mappings.toml...")
with open("packages/package_mappings.toml") as f:
    toml_data = toml.load(f)

fixes = []

for package_name, entry in toml_data.items():
    tags = entry.get("tags", [])
    original_tags = tags.copy()

    # If package has pm:homebrew:cask, convert it properly
    if "pm:homebrew:cask" in tags:
        # Remove pm:homebrew:cask
        tags.remove("pm:homebrew:cask")

        # Ensure cat:cask is present
        if "cat:cask" not in tags:
            tags.append("cat:cask")

        # Ensure os:macos is present
        if "os:macos" not in tags:
            tags.append("os:macos")

        # Ensure pm:homebrew:macos is present
        if "pm:homebrew:macos" not in tags:
            tags.append("pm:homebrew:macos")

    # If package has cat:cask, ensure it has proper homebrew macos tags
    if "cat:cask" in tags:
        # Ensure os:macos is present
        if "os:macos" not in tags:
            tags.append("os:macos")

        # Ensure pm:homebrew:macos is present
        if "pm:homebrew:macos" not in tags:
            tags.append("pm:homebrew:macos")

    # Update if changed
    if tags != original_tags:
        entry["tags"] = tags
        fixes.append(package_name)
        print(
            f"Fixed {package_name}: ensured proper cask tags (cat:cask + os:macos + pm:homebrew:macos)"
        )

# Save updated TOML
if fixes:
    print(f"\nSaving {len(fixes)} fixes to package_mappings.toml...")
    with open("packages/package_mappings.toml", "w") as f:
        toml.dump(toml_data, f)
    print("Done!")
else:
    print("\nNo fixes needed.")
