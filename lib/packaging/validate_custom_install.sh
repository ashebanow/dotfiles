#!/usr/bin/env bash
#
# Validate custom installation configuration file
# Checks JSON syntax and structure of packages/custom_install.json
#

set -euo pipefail

echo "Validating custom installation configuration..."

if [[ ! -f "packages/custom_install.json" ]]; then
    echo "✅ No custom installation file found (this is ok)"
    exit 0
fi

# Basic JSON validation
if command -v jq >/dev/null 2>&1; then
    if jq empty packages/custom_install.json >/dev/null 2>&1; then
        echo "✅ JSON syntax is valid"
    else
        echo "❌ JSON syntax error in packages/custom_install.json"
        exit 1
    fi
    
    # Check structure
    if jq -e '.packages' packages/custom_install.json >/dev/null 2>&1; then
        PACKAGE_COUNT=$(jq '.packages | length' packages/custom_install.json)
        echo "✅ Found $PACKAGE_COUNT custom packages"
    else
        echo "❌ Missing 'packages' key in custom_install.json"
        exit 1
    fi
else
    echo "⚠️  jq not available, cannot validate JSON structure"
    echo "✅ File exists and is readable"
fi

echo ""
echo "Custom packages:"
if command -v jq >/dev/null 2>&1; then
    jq -r '.packages | keys[]' packages/custom_install.json | sed 's/^/  - /'
else
    echo "  (install jq to see package list)"
fi