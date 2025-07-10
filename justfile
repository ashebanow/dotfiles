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
    uv run bin/package_analysis_cli.py \
        --package-lists packages/Brewfile.in packages/Brewfile-darwin tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile \
        --output packages/package_mappings.toml.new \
        --cache packages/repology_cache.json \
        --tag-cache packages/tag_cache.json
    echo "Generated packages/package_mappings.toml.new"
    echo "Review changes with: diff packages/package_mappings.toml packages/package_mappings.toml.new"
    echo "Apply changes with: mv packages/package_mappings.toml.new packages/package_mappings.toml"

# UV manages Python and dependencies automatically

# Regenerate package_mappings.toml and automatically apply changes
[group('package-management')]
regen-toml-apply:
    #!/usr/bin/env bash
    echo "Regenerating and applying package_mappings.toml..."
    uv run bin/package_analysis_cli.py \
        --package-lists packages/Brewfile.in packages/Brewfile-darwin tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile \
        --output packages/package_mappings.toml \
        --cache packages/repology_cache.json \
        --tag-cache packages/tag_cache.json
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
    uv run bin/package_analysis_cli.py \
        --package {{packages}} \
        --output packages/temp_packages.toml \
        --cache packages/repology_cache.json \
        --tag-cache packages/tag_cache.json
    echo "Generated packages/temp_packages.toml with package data"

# Add custom installation entry interactively
[group('package-management')]
add-custom-install:
    @./lib/packaging/add_custom_install.sh

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
    @./lib/packaging/validate_custom_install.sh

# Generate filtered package files from TOML (smart platform detection)
[group('package-management')]
generate-package-lists:
    #!/usr/bin/env bash
    echo "Generating platform-specific package lists from TOML (using tagged system)..."
    uv run bin/package_generators_tagged.py \
        --toml packages/package_mappings.toml \
        --output-dir packages
    echo "✓ Generated package lists for current platform using tagged filtering"


# Preview what package files would be generated
[group('package-management')]
preview-package-files:
    #!/usr/bin/env bash
    echo "Previewing package file generation..."
    uv run bin/package_generators_tagged.py \
        --toml packages/package_mappings.toml \
        --print-only

# Generate only custom installation file
[group('package-management')]
generate-custom-only:
    #!/usr/bin/env bash
    echo "Generating custom installation file..."
    uv run bin/package_generators_tagged.py \
        --toml packages/package_mappings.toml \
        --output-dir packages \
        --target custom

# Validate package mapping roundtrip
[group('package-management')]
validate-roundtrip:
    #!/usr/bin/env bash
    # Skip validation on Linux - package generator correctly prioritizes native packages
    if [[ "$(uname -s)" == "Linux" ]]; then
        echo "ℹ️  Skipping roundtrip validation on Linux"
        echo "The package generator correctly prioritizes native packages (apt) over Homebrew on Linux"
        echo "This validation is designed for macOS where Homebrew is the primary package manager"
        exit 0
    fi
    
    echo "Validating package mapping roundtrip..."
    uv run bin/package_analysis_cli.py \
        --validate \
        --package-lists packages/Brewfile.in tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile \
        --cache packages/repology_cache.json \
        --tag-cache packages/tag_cache.json

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
    @./lib/testing/run_install_tests.sh

# Run Python unit tests with pytest
[group('testing')]
test-python:
    @echo "Running Python unit tests..."
    @./test.sh unit

# Run Python tests with coverage
[group('testing')]
test-python-coverage:
    @echo "Running Python tests with coverage..."
    @./test.sh coverage

# Run code quality checks (black, ruff, mypy)
[group('testing')]
test-lint:
    @echo "Running code quality checks..."
    @./test.sh lint

# Run all tests (package management + install scripts)
[group('testing')]
test-all: test-packages test-install
    @echo "✓ All tests completed"

# Run comprehensive tests (package management + install scripts + Python)
[group('testing')]
test-all-comprehensive: test-packages test-install test-python
    @echo "✓ All comprehensive tests completed (package + install + Python)"

# Run fast Python tests in parallel
[group('testing')]
test-python-fast:
    @echo "Running Python tests in parallel..."
    @./test.sh fast

# Test GitHub Actions with act (local only)
[group('testing')]
test-actions:
    @echo "Testing GitHub Actions with act..."
    @./test.sh actions

# Format code and run linting
[group('testing')]
format-and-lint:
    @echo "Formatting code and running quality checks..."
    @./test.sh format
    @./test.sh lint

# ===== DEBUGGING & DEVELOPMENT =====

# Debug specific package analysis
[group('debug')]
debug-package package:
    #!/usr/bin/env bash
    echo "Debugging package: {{package}}"
    uv run bin/package_analysis_cli.py --package {{package}} --cache tests/debug_cache.json --tag-cache packages/tag_cache.json

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
    rm -f packages/repology_cache.json tests/debug_cache.json
    rm -f packages/temp_packages.toml packages/package_mappings.toml.new
    rm -rf tests/generated_packages/
    rm -rf tests/temp_test_output/
    echo "✓ Cleanup complete"

# Clean expired cache entries (keeps fresh entries)
[group('maintenance')]
clean-expired-cache:
    #!/usr/bin/env bash
    echo "Cleaning expired cache entries..."
    uv run bin/clean_cache.py packages/repology_cache.json
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
    uv run bin/refresh_cache_segment.py --segment {{segment}} --cache packages/repology_cache.json
    echo "✓ Cache segment {{segment}} refreshed"

# Show cache statistics and segment information
[group('maintenance')]
cache-stats:
    #!/usr/bin/env bash
    echo "Package Cache Statistics"
    echo "======================="
    
    if [[ -f "packages/repology_cache.json" ]]; then
            uv run bin/clean_cache.py packages/repology_cache.json --stats-only
    else
        echo "❌ No cache file found (packages/repology_cache.json)"
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
    @./lib/development/check_dependencies.sh

# Install Python dependencies
[group('development')]
install-deps:
    @echo "Installing Python dependencies..."
    @uv run -m pip install --user toml requests

# Fix SSL issues (common on macOS with LibreSSL)
[group('development')]
fix-ssl:
    @./lib/development/fix_ssl_issues.sh


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
