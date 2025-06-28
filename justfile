#!/usr/bin/env just --justfile

# Default recipe to show available commands
default:
    @just --list

# ===== PACKAGE MANAGEMENT =====

# Regenerate package_mappings.toml from all package files
[group('package-management')]
regen-toml:
    #!/usr/bin/env bash
    {{_check_venv}}
    echo "Regenerating package_mappings.toml from package files..."
    echo "Using Python: {{_python_cmd}}"
    {{_python_cmd}} bin/package_analysis.py \
        --package-lists packages/Brewfile.in packages/Brewfile-darwin tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile \
        --output packages/package_mappings.toml.new \
        --cache packages/.repology_cache.json
    echo "Generated packages/package_mappings.toml.new"
    echo "Review changes with: diff packages/package_mappings.toml packages/package_mappings.toml.new"
    echo "Apply changes with: mv packages/package_mappings.toml.new packages/package_mappings.toml"

# Setup Python virtual environment for package management
[group('setup')]
setup-python:
    #!/usr/bin/env bash
    # Ensure uv is available
    if ! command -v uv >/dev/null 2>&1; then
        if command -v brew >/dev/null 2>&1; then
            echo "Installing uv via Homebrew..."
            brew install uv
        else
            echo "Error: uv is required but not installed."
            echo "Please install uv: https://docs.astral.sh/uv/getting-started/installation/"
            echo "Or install Homebrew first: https://brew.sh/"
            exit 1
        fi
    fi
    
    # Check if UV has Python installed, if not install it
    if ! uv python list | grep -q "3\.11"; then
        echo "Installing Python 3.11 via UV..."
        if ! uv python install 3.11; then
            echo "Error: Failed to install Python 3.11 via UV"
            exit 1
        fi
    fi
    
    if [ ! -d ".venv" ]; then
        echo "Creating Python virtual environment with uv..."
        if ! uv venv .venv --python 3.11; then
            echo "Error: Failed to create virtual environment"
            exit 1
        fi
        echo "Installing dependencies..."
        if ! uv pip install toml requests; then
            echo "Error: Failed to install Python dependencies"
            exit 1
        fi
        echo "✓ Python environment ready"
    else
        echo "✓ Python environment already exists"
        # Verify dependencies are available
        if ! .venv/bin/python3 -c "import requests, toml" 2>/dev/null; then
            echo "Installing missing dependencies..."
            if ! uv pip install toml requests; then
                echo "Error: Failed to install Python dependencies"
                exit 1
            fi
        fi
    fi
    
    # Final verification that everything works
    if ! .venv/bin/python3 -c "import requests, toml; print('✓ Virtual environment ready with all dependencies')" 2>/dev/null; then
        echo "Error: Virtual environment setup failed - dependencies not available"
        echo "Try removing .venv directory and running 'just setup-python' again"
        exit 1
    fi

# Helper to check virtual environment exists
_check_venv := "if [[ ! -f '.venv/bin/python3' ]]; then echo 'ERROR: Python virtual environment not found. Run: just setup-python'; exit 1; fi"

# Python executable using virtual environment (required for proper dependencies)
_python_cmd := ".venv/bin/python3"

# Regenerate package_mappings.toml and automatically apply changes
[group('package-management')]
regen-toml-apply:
    #!/usr/bin/env bash
    {{_check_venv}}
    echo "Regenerating and applying package_mappings.toml..."
    echo "Using Python: {{_python_cmd}}"
    {{_python_cmd}} bin/package_analysis.py \
        --package-lists packages/Brewfile.in packages/Brewfile-darwin tests/assets/legacy_packages/Archfile tests/assets/legacy_packages/Aptfile tests/assets/legacy_packages/Flatfile \
        --output packages/package_mappings.toml \
        --cache packages/.repology_cache.json
    echo "✓ Updated packages/package_mappings.toml"

# Complete workflow: regenerate TOML and generate package lists
[group('package-management')]
regen-and-generate:
    @echo "Running complete package management workflow..."
    @just setup-python
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
    just setup-python
    {{_check_venv}}
    echo "Adding packages to TOML: {{packages}}"
    echo "Using Python: {{_python_cmd}}"
    {{_python_cmd}} bin/package_analysis.py \
        --package {{packages}} \
        --output temp_packages.toml \
        --cache packages/.repology_cache.json
    echo "Generated temp_packages.toml with package data"

# Generate filtered package files from TOML (smart platform detection)
[group('package-management')]
generate-package-lists:
    #!/usr/bin/env bash
    {{_check_venv}}
    echo "Generating platform-specific package lists from TOML..."
    echo "Using Python: {{_python_cmd}}"
    {{_python_cmd}} bin/package_generators.py \
        --toml packages/package_mappings.toml \
        --original-brewfile packages/Brewfile.in \
        --output-dir packages
    echo "✓ Generated package lists for current platform"

# Generate filtered package files from TOML (legacy - outputs to subdirectory)
[group('package-management')]
generate-package-files:
    #!/usr/bin/env bash
    echo "Generating package files from TOML..."
    {{_python_cmd}} bin/package_generators.py \
        --toml packages/package_mappings.toml \
        --original-brewfile packages/Brewfile.in \
        --output-dir tests/generated_packages
    echo "✓ Generated package files in tests/generated_packages/"

# Preview what package files would be generated
[group('package-management')]
preview-package-files:
    #!/usr/bin/env bash
    echo "Previewing package file generation..."
    {{_python_cmd}} bin/package_generators.py \
        --toml packages/package_mappings.toml \
        --original-brewfile packages/Brewfile.in \
        --print-only

# Validate package mapping roundtrip
[group('package-management')]
validate-roundtrip:
    #!/usr/bin/env bash
    echo "Validating package mapping roundtrip..."
    {{_python_cmd}} bin/package_analysis.py \
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
    {{_check_venv}}
    echo "Debugging package: {{package}}"
    echo "Using Python: {{_python_cmd}}"
    {{_python_cmd}} bin/package_analysis.py --package {{package}} --cache tests/.debug_cache.json

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
    rm -f temp_packages.toml packages/package_mappings.toml.new
    rm -rf tests/generated_packages/
    rm -rf tests/temp_test_output/
    echo "✓ Cleanup complete"

# Clean expired cache entries (keeps fresh entries)
[group('maintenance')]
clean-expired-cache:
    #!/usr/bin/env bash
    echo "Cleaning expired cache entries..."
    echo "Using Python: {{_python_cmd}}"
    {{_python_cmd}} bin/clean_cache.py packages/.repology_cache.json
    echo "✓ Expired cache entries cleaned"

# Refresh a specific segment of the cache (0-6)
[group('maintenance')]
refresh-cache-segment segment:
    #!/usr/bin/env bash
    echo "Refreshing cache segment {{segment}}..."
    echo "Using Python: {{_python_cmd}}"
    if [[ ! -f "bin/refresh_cache_segment.py" ]]; then
        echo "Error: bin/refresh_cache_segment.py not found"
        echo "This script is created by the GitHub Action workflow"
        echo "You can manually refresh cache with: just clean-expired-cache && just regen-toml"
        exit 1
    fi
    {{_python_cmd}} bin/refresh_cache_segment.py --segment {{segment}} --cache packages/.repology_cache.json
    echo "✓ Cache segment {{segment}} refreshed"

# Show cache statistics and segment information
[group('maintenance')]
cache-stats:
    #!/usr/bin/env bash
    echo "Package Cache Statistics"
    echo "======================="
    
    if [[ -f "packages/.repology_cache.json" ]]; then
        echo "Using Python: {{_python_cmd}}"
        {{_python_cmd}} bin/clean_cache.py packages/.repology_cache.json --stats-only
    else
        echo "❌ No cache file found (packages/.repology_cache.json)"
        echo "Run 'just regen-toml' to create initial cache"
    fi

# ===== DEVELOPMENT HELPERS =====

# Check if required Python dependencies are available
[group('development')]
check-deps:
    #!/usr/bin/env bash
    echo "Checking Python dependencies..."
    {{_python_cmd}} -c "import toml; print('✓ toml library available')" 2>/dev/null || echo "✗ toml library missing (pip install toml)"
    {{_python_cmd}} -c "import requests; print('✓ requests library available')" 2>/dev/null || echo "✗ requests library missing (pip install requests)"
    
    echo "Checking SSL configuration..."
    {{_python_cmd}} -c "import ssl; print(f'✓ SSL version: {ssl.OPENSSL_VERSION}')" 2>/dev/null || echo "✗ SSL check failed"
    {{_python_cmd}} -c "import urllib3; print(f'urllib3 version: {urllib3.__version__}')" 2>/dev/null || echo "urllib3 not available"
    
    # Check for SSL issues
    if {{_python_cmd}} -c "import urllib3; assert urllib3.__version__.startswith('2.')" 2>/dev/null; then
        if {{_python_cmd}} -c "import ssl; assert 'LibreSSL' in ssl.OPENSSL_VERSION" 2>/dev/null; then
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
    @{{_python_cmd}} -m pip install --user toml requests

# Fix SSL issues (common on macOS with LibreSSL)
[group('development')]
fix-ssl:
    #!/usr/bin/env bash
    echo "Fixing SSL configuration issues..."
    
    # Check current status
    echo "Current SSL setup:"
    {{_python_cmd}} -c "import ssl; print(f'  SSL: {ssl.OPENSSL_VERSION}')" 2>/dev/null || echo "  SSL: Failed to detect"
    {{_python_cmd}} -c "import urllib3; print(f'  urllib3: {urllib3.__version__}')" 2>/dev/null || echo "  urllib3: Not installed"
    
    echo
    echo "Applying fix: Downgrade urllib3 to v1.x (compatible with LibreSSL)"
    {{_python_cmd}} -m pip install --user 'urllib3<2.0' 'requests>=2.28.0'
    
    echo
    echo "Verifying fix..."
    {{_python_cmd}} -c "import urllib3; print(f'✓ urllib3 version: {urllib3.__version__}')"
    {{_python_cmd}} -c "import ssl, requests; print('✓ SSL/requests working'); requests.get('https://httpbin.org/get', timeout=5)" 2>/dev/null && echo "✓ HTTPS requests working" || echo "✗ HTTPS requests still failing"


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
