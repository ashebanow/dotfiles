#!/usr/bin/env just --justfile

# Default recipe to show available commands
default:
    @just --list

# ===== PACKAGE MANAGEMENT =====

# Regenerate package_mappings.toml from all package files
[group('package-management')]
regen-toml:
    #!/usr/bin/env bash
    echo "Regenerating package_mappings.toml from package files..."
    uv run bin/package_analysis.py \
        --package-lists packages/Brewfile.in packages/Brewfile-darwin tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile \
        --output packages/package_mappings.toml.new \
        --cache packages/.repology_cache.json
    echo "Generated packages/package_mappings.toml.new"
    echo "Review changes with: diff packages/package_mappings.toml packages/package_mappings.toml.new"
    echo "Apply changes with: mv packages/package_mappings.toml.new packages/package_mappings.toml"

# UV manages Python and dependencies automatically

# Regenerate package_mappings.toml and automatically apply changes
[group('package-management')]
regen-toml-apply:
    #!/usr/bin/env bash
    echo "Regenerating and applying package_mappings.toml..."
    uv run bin/package_analysis.py \
        --package-lists packages/Brewfile.in packages/Brewfile-darwin tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile \
        --output packages/package_mappings.toml \
        --cache packages/.repology_cache.json
    echo "✓ Updated packages/package_mappings.toml"

# Complete workflow: regenerate TOML and generate package lists
[group('package-management')]
regen-and-generate:
    @echo "Running complete package management workflow..."
    @just regen-toml-apply
    @just generate-package-lists
    @echo "✓ Complete workflow finished"

# Add specific packages to TOML (for debugging/testing)
[group('package-management')]
add-packages *packages:
    #!/usr/bin/env bash
    if [[ -z "{{packages}}" ]]; then
        echo "Usage: just add-packages package1 [package2 ...]"
        echo "Example: just add-packages zellij bat"
        exit 1
    fi
    echo "Adding packages to TOML: {{packages}}"
    uv run bin/package_analysis.py \
        --package {{packages}} \
        --output packages/temp_packages.toml \
        --cache packages/.repology_cache.json
    echo "Generated packages/temp_packages.toml with package data"

# Add custom installation entry interactively
[group('package-management')]
add-custom-install:
    #!/usr/bin/env bash
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

# Install only custom packages
[group('package-management')]
install-custom-only:
    #!/usr/bin/env bash
    echo "Installing custom packages only..."
    if [[ -f "packages/Customfile" ]]; then
        ./lib/install/custom.sh packages/Customfile
    else
        echo "No Customfile found. Run 'just generate-package-lists' first."
        exit 1
    fi

# Edit custom installation configuration
[group('package-management')]
edit-custom-install:
    #!/usr/bin/env bash
    if [[ ! -f "packages/custom_install.json" ]]; then
        echo "No custom installation file found. Create one with: just add-custom-install"
        exit 1
    fi
    
    if command -v code >/dev/null 2>&1; then
        code packages/custom_install.json
    elif [[ -n "${EDITOR:-}" ]]; then
        "$EDITOR" packages/custom_install.json
    else
        echo "Please edit packages/custom_install.json manually"
        echo "Current contents:"
        cat packages/custom_install.json
    fi

# Validate custom installation configuration
[group('package-management')]
validate-custom-install:
    #!/usr/bin/env bash
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

# Generate filtered package files from TOML (smart platform detection)
[group('package-management')]
generate-package-lists:
    #!/usr/bin/env bash
    echo "Generating platform-specific package lists from TOML..."
    uv run bin/package_generators.py \
        --toml packages/package_mappings.toml \
        --original-brewfile packages/Brewfile.in \
        --output-dir packages
    echo "✓ Generated package lists for current platform"

# Generate filtered package files from TOML (legacy - outputs to subdirectory)
[group('package-management')]
generate-package-files:
    #!/usr/bin/env bash
    echo "Generating package files from TOML..."
    uv run bin/package_generators.py \
        --toml packages/package_mappings.toml \
        --original-brewfile packages/Brewfile.in \
        --output-dir tests/generated_packages
    echo "✓ Generated package files in tests/generated_packages/"

# Preview what package files would be generated
[group('package-management')]
preview-package-files:
    #!/usr/bin/env bash
    echo "Previewing package file generation..."
    uv run bin/package_generators.py \
        --toml packages/package_mappings.toml \
        --original-brewfile packages/Brewfile.in \
        --print-only

# Generate only custom installation file
[group('package-management')]
generate-custom-only:
    #!/usr/bin/env bash
    echo "Generating custom installation file..."
    uv run bin/package_generators.py \
        --toml packages/package_mappings.toml \
        --output-dir packages \
        --target custom

# Validate package mapping roundtrip
[group('package-management')]
validate-roundtrip:
    #!/usr/bin/env bash
    echo "Validating package mapping roundtrip..."
    uv run bin/package_analysis.py \
        --validate \
        --package-lists packages/Brewfile.in tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile

# ===== TESTING =====

# Run all package management tests
[group('testing')]
test-packages:
    @echo "Running package management tests..."
    @./tests/test_package_management.sh all

# Run specific package management test
[group('testing')]
test-packages-specific test_name:
    @echo "Running package management test: {{test_name}}"
    @./tests/test_package_management.sh {{test_name}}

# Run install script tests (if they exist)
[group('testing')]
test-install:
    #!/usr/bin/env bash
    if [[ -f "tests/test_install.sh" ]]; then
        echo "Running install script tests..."
        ./tests/test_install.sh
    elif [[ -d "lib/install/tests" ]]; then
        echo "Running tests in lib/install/tests..."
        for test in lib/install/tests/*.sh; do
            if [[ -f "$test" ]]; then
                echo "Running $test..."
                bash "$test"
            fi
        done
    else
        echo "No install tests found."
        echo "Create tests/test_install.sh or tests in lib/install/tests/"
    fi

# Run all tests (package management + install scripts)
[group('testing')]
test-all: test-packages test-install
    @echo "✓ All tests completed"

# ===== DEBUGGING & DEVELOPMENT =====

# Debug specific package analysis
[group('debug')]
debug-package package:
    #!/usr/bin/env bash
    echo "Debugging package: {{package}}"
    uv run bin/package_analysis.py --package {{package}} --cache tests/.debug_cache.json

# Show package mapping for specific package
[group('debug')]
show-package package:
    #!/usr/bin/env bash
    if [[ -f "packages/package_mappings.toml" ]]; then
        echo "Package mapping for {{package}}:"
        grep -A 20 "^\[{{package}}\]" packages/package_mappings.toml || echo "Package not found in TOML"
    else
        echo "packages/package_mappings.toml not found"
    fi

# Clean up cache and temporary files
[group('maintenance')]
clean:
    #!/usr/bin/env bash
    echo "Cleaning up cache and temporary files..."
    rm -f packages/.repology_cache.json tests/.debug_cache.json
    rm -f packages/temp_packages.toml packages/package_mappings.toml.new
    rm -rf tests/generated_packages/
    rm -rf tests/temp_test_output/
    echo "✓ Cleanup complete"

# Clean expired cache entries (keeps fresh entries)
[group('maintenance')]
clean-expired-cache:
    #!/usr/bin/env bash
    echo "Cleaning expired cache entries..."
    uv run bin/clean_cache.py packages/.repology_cache.json
    echo "✓ Expired cache entries cleaned"

# Refresh a specific segment of the cache (0-6)
[group('maintenance')]
refresh-cache-segment segment:
    #!/usr/bin/env bash
    echo "Refreshing cache segment {{segment}}..."
    if [[ ! -f "bin/refresh_cache_segment.py" ]]; then
        echo "Error: bin/refresh_cache_segment.py not found"
        echo "This script is created by the GitHub Action workflow"
        echo "You can manually refresh cache with: just clean-expired-cache && just regen-toml"
        exit 1
    fi
    uv run bin/refresh_cache_segment.py --segment {{segment}} --cache packages/.repology_cache.json
    echo "✓ Cache segment {{segment}} refreshed"

# Show cache statistics and segment information
[group('maintenance')]
cache-stats:
    #!/usr/bin/env bash
    echo "Package Cache Statistics"
    echo "======================="
    
    if [[ -f "packages/.repology_cache.json" ]]; then
            uv run bin/clean_cache.py packages/.repology_cache.json --stats-only
    else
        echo "❌ No cache file found (packages/.repology_cache.json)"
        echo "Run 'just regen-toml' to create initial cache"
    fi

# Check if package files need updating
[group('maintenance')]
check-updates:
    #!/usr/bin/env bash
    echo "Checking for package updates..."
    ./bin/check_package_updates.sh

# ===== DEVELOPMENT HELPERS =====

# Check if required Python dependencies are available
[group('development')]
check-deps:
    #!/usr/bin/env bash
    echo "Checking Python dependencies..."
    uv run -c "import toml; print('✓ toml library available')" 2>/dev/null || echo "✗ toml library missing (pip install toml)"
    uv run -c "import requests; print('✓ requests library available')" 2>/dev/null || echo "✗ requests library missing (pip install requests)"
    
    echo "Checking SSL configuration..."
    uv run -c "import ssl; print(f'✓ SSL version: {ssl.OPENSSL_VERSION}')" 2>/dev/null || echo "✗ SSL check failed"
    uv run -c "import urllib3; print(f'urllib3 version: {urllib3.__version__}')" 2>/dev/null || echo "urllib3 not available"
    
    # Check for SSL issues
    if uv run -c "import urllib3; assert urllib3.__version__.startswith('2.')" 2>/dev/null; then
        if uv run -c "import ssl; assert 'LibreSSL' in ssl.OPENSSL_VERSION" 2>/dev/null; then
            echo "⚠️  SSL Issue Detected: urllib3 v2 + LibreSSL (common on macOS)"
            echo "   Fix with: just fix-ssl"
        fi
    fi
    
    echo "Checking tools..."
    command -v just >/dev/null 2>&1 && echo "✓ just available" || echo "✗ just not found"
    command -v python3 >/dev/null 2>&1 && echo "✓ python3 available" || echo "✗ python3 not found"

# Install Python dependencies
[group('development')]
install-deps:
    @echo "Installing Python dependencies..."
    @uv run -m pip install --user toml requests

# Fix SSL issues (common on macOS with LibreSSL)
[group('development')]
fix-ssl:
    #!/usr/bin/env bash
    echo "Fixing SSL configuration issues..."
    
    # Check current status
    echo "Current SSL setup:"
    uv run -c "import ssl; print(f'  SSL: {ssl.OPENSSL_VERSION}')" 2>/dev/null || echo "  SSL: Failed to detect"
    uv run -c "import urllib3; print(f'  urllib3: {urllib3.__version__}')" 2>/dev/null || echo "  urllib3: Not installed"
    
    echo
    echo "Applying fix: Downgrade urllib3 to v1.x (compatible with LibreSSL)"
    uv run -m pip install --user 'urllib3<2.0' 'requests>=2.28.0'
    
    echo
    echo "Verifying fix..."
    uv run -c "import urllib3; print(f'✓ urllib3 version: {urllib3.__version__}')"
    uv run -c "import ssl, requests; print('✓ SSL/requests working'); requests.get('https://httpbin.org/get', timeout=5)" 2>/dev/null && echo "✓ HTTPS requests working" || echo "✗ HTTPS requests still failing"


# Show project structure for package management
[group('development')]
show-structure:
    #!/usr/bin/env bash
    echo "Package Management File Structure:"
    echo "=================================="
    tree -I '__pycache__|*.pyc' --dirsfirst -a -L 3 \
        bin/ tests/ lib/install/ lib/packaging/ \
        packages/ 2>/dev/null || \
    find bin tests lib/install -type f -name "*.py" -o -name "*.sh" | sort

# ===== INSTALL INTEGRATION =====

# Generate package lists and install packages (smart platform detection)
[group('install')]
install-packages:
    #!/usr/bin/env bash
    echo "Generating and installing packages for current platform..."
    just generate-package-lists
    echo "Package lists generated. Use your system's package installation method to install."
    echo "Example: For Homebrew: brew bundle --file=packages/Brewfile"

# Install custom packages only
[group('install')]
install-custom:
    #!/usr/bin/env bash
    echo "Installing custom packages..."
    just generate-custom-only
    if [[ -f "packages/Customfile" ]]; then
        bash lib/install/custom.sh
    else
        echo "No custom packages to install"
    fi

# ===== EXAMPLES =====

# Example workflow: Add new package and regenerate
[group('examples')]
example-add-package:
    @echo "Example: Adding a new package and regenerating TOML"
    @echo "1. just add-packages neovim"
    @echo "2. just regen-toml"
    @echo "3. just validate-roundtrip"
    @echo "4. just generate-package-lists"

# Example workflow: Debug package issues
[group('examples')]
example-debug:
    @echo "Example: Debugging package mapping issues"
    @echo "1. just debug-package zellij"
    @echo "2. just show-package zellij"
    @echo "3. just test-packages-specific single"

# Example workflow: Complete system setup
[group('examples')]
example-complete-setup:
    @echo "Example: Complete package management setup"
    @echo "1. just regen-and-generate"
    @echo "2. just validate-roundtrip"
    @echo "3. just install-packages"
