#!/usr/bin/env bash
#
# Interactive script to add custom installation entries to packages/custom_install.json
# Uses gum for interactive prompts and creates structured JSON configuration
#

set -euo pipefail

echo "Adding custom installation entry..."

if ! command -v gum >/dev/null 2>&1; then
    echo "Error: gum is required for interactive custom installation setup"
    echo "Install gum first: brew install gum"
    exit 1
fi

# Get package name
PACKAGE_NAME=$(gum input --placeholder "Package name (e.g., tailscale)")
if [[ -z "$PACKAGE_NAME" ]]; then
    echo "Package name is required"
    exit 1
fi

# Get description
DESCRIPTION=$(gum input --placeholder "Package description" --value "")

# Get priority
PRIORITY=$(gum choose --header "Custom install priority:" "always" "fallback" "never")

# Get confirmation requirement
REQUIRES_CONFIRMATION=$(gum choose --header "Require user confirmation?" "false" "true")

# Get install condition (optional)
INSTALL_CONDITION=$(gum input --placeholder "Install condition (optional, e.g. 'test \$(uname) = Darwin')" --value "")

echo ""
echo "Setting up platform-specific commands..."
echo "Press Enter to skip a platform, or provide commands (one per line, empty line to finish)"
echo ""

# Helper function to get commands for a platform
get_platform_commands() {
    local platform_name="$1"
    local platform_key="$2"
    
    echo "Commands for $platform_name:"
    local commands=()
    while true; do
        local cmd=$(gum input --placeholder "Command $(( ${#commands[@]} + 1 )) (empty to finish)" --value "")
        if [[ -z "$cmd" ]]; then
            break
        fi
        commands+=("$cmd")
    done
    
    if [[ ${#commands[@]} -gt 0 ]]; then
        printf '    "%s": [\n' "$platform_key"
        for cmd in "${commands[@]}"; do
            printf '      "%s",\n' "$cmd"
        done
        printf '    ],\n'
    fi
}

# Create JSON structure
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
  "packages": {
    "$PACKAGE_NAME": {
EOF

if [[ -n "$DESCRIPTION" ]]; then
    echo "      \"description\": \"$DESCRIPTION\"," >> "$TEMP_JSON"
fi

echo '      "custom-install": {' >> "$TEMP_JSON"

# Get platform-specific commands
if gum confirm "Add macOS-specific commands?"; then
    get_platform_commands "macOS" "is_darwin" >> "$TEMP_JSON"
fi

if gum confirm "Add Linux-specific commands?"; then
    get_platform_commands "Linux" "is_linux" >> "$TEMP_JSON"
fi

if gum confirm "Add Arch Linux-specific commands?"; then
    get_platform_commands "Arch Linux" "is_arch_like" >> "$TEMP_JSON"
fi

if gum confirm "Add Debian/Ubuntu-specific commands?"; then
    get_platform_commands "Debian/Ubuntu" "is_debian_like" >> "$TEMP_JSON"
fi

if gum confirm "Add Fedora-specific commands?"; then
    get_platform_commands "Fedora" "is_fedora_like" >> "$TEMP_JSON"
fi

if gum confirm "Add default commands (fallback for all platforms)?"; then
    get_platform_commands "Default (all platforms)" "default" >> "$TEMP_JSON"
fi

echo '      },' >> "$TEMP_JSON"

if [[ "$PRIORITY" != "always" ]]; then
    echo "      \"custom-install-priority\": \"$PRIORITY\"," >> "$TEMP_JSON"
fi

if [[ "$REQUIRES_CONFIRMATION" == "true" ]]; then
    echo "      \"requires-confirmation\": true," >> "$TEMP_JSON"
fi

if [[ -n "$INSTALL_CONDITION" ]]; then
    echo "      \"install-condition\": \"$INSTALL_CONDITION\"," >> "$TEMP_JSON"
fi

# Remove trailing comma and close JSON
sed -i '' '$ s/,$//' "$TEMP_JSON" 2>/dev/null || sed -i '$ s/,$//' "$TEMP_JSON"

cat >> "$TEMP_JSON" << EOF
    }
  }
}
EOF

# Merge with existing custom_install.json
if [[ -f "packages/custom_install.json" ]]; then
    # Use jq to merge if available, otherwise manual merge
    if command -v jq >/dev/null 2>&1; then
        MERGED=$(jq -s '.[0].packages * .[1].packages | {packages: .}' packages/custom_install.json "$TEMP_JSON")
        echo "$MERGED" > packages/custom_install.json
    else
        echo "Warning: jq not available, creating new custom_install.json file"
        cp "$TEMP_JSON" packages/custom_install.json
    fi
else
    cp "$TEMP_JSON" packages/custom_install.json
fi

rm "$TEMP_JSON"

echo ""
echo "✅ Added custom installation entry for: $PACKAGE_NAME"
echo "📝 Updated: packages/custom_install.json"
echo ""
echo "Next steps:"
echo "  1. Review the entry: cat packages/custom_install.json"
echo "  2. Regenerate TOML: just regen-toml"
echo "  3. Test installation: just install-custom-only"