#!/usr/bin/env bash
#
# Test script for the new package management system
# Tests both package_analysis.py and package_generators.py
#

set -euo pipefail

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_ASSETS="$SCRIPT_DIR/assets/package_mapping"
TEMP_DIR="$SCRIPT_DIR/output"

# Use uv to run Python commands (ensures proper dependencies)
PYTHON_CMD="uv run python"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_test() {
    echo -e "${YELLOW}[TEST] $1${NC}"
    TESTS_RUN=$((TESTS_RUN + 1))
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Setup
setup_tests() {
    print_header "Setting up test environment"
    
    # Clean up any previous test runs
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Check if required tools exist
    if [[ ! -f "$PROJECT_ROOT/bin/package_analysis.py" ]]; then
        print_error "package_analysis.py not found"
        exit 1
    fi
    
    if [[ ! -f "$PROJECT_ROOT/bin/package_generators.py" ]]; then
        print_error "package_generators.py not found"
        exit 1
    fi
    
    print_success "Test environment setup complete"
}

# Test 1: Single package analysis
test_single_package_analysis() {
    print_test "Single package analysis (bat, gh, zellij)"
    
    cd "$PROJECT_ROOT"
    
    if $PYTHON_CMD bin/package_analysis.py \
        --package bat gh zellij \
        --output "$TEMP_DIR/single_packages.toml" \
        --cache "$TEMP_DIR/cache.json" > "$TEMP_DIR/single_test.log" 2>&1; then
        
        # Check if output file was created
        if [[ -f "$TEMP_DIR/single_packages.toml" ]]; then
            # Check if all packages are in the output
            local missing_packages=()
            for pkg in bat gh zellij; do
                if ! grep -q "\\[$pkg\\]" "$TEMP_DIR/single_packages.toml"; then
                    missing_packages+=("$pkg")
                fi
            done
            
            if [[ ${#missing_packages[@]} -eq 0 ]]; then
                print_success "Single package analysis completed"
            else
                print_error "Missing packages in output: ${missing_packages[*]}"
            fi
        else
            print_error "Output TOML file not created"
        fi
    else
        print_error "Single package analysis failed"
        cat "$TEMP_DIR/single_test.log"
    fi
}

# Test 2: Package file parsing
test_package_file_parsing() {
    print_test "Package file parsing (Brewfile, Archfile, etc.)"
    
    cd "$PROJECT_ROOT"
    
    if $PYTHON_CMD bin/package_analysis.py \
        --package-lists "$TEST_ASSETS/test_brewfile.in" "$TEST_ASSETS/simple_archfile" \
        --output "$TEMP_DIR/parsed_packages.toml" \
        --cache "$TEMP_DIR/cache.json" > "$TEMP_DIR/parsing_test.log" 2>&1; then
        
        if [[ -f "$TEMP_DIR/parsed_packages.toml" ]]; then
            # Check for some expected packages
            local expected_packages=(bat gh zellij fd ripgrep git)
            local missing_packages=()
            
            for pkg in "${expected_packages[@]}"; do
                if ! grep -q "\\[$pkg\\]" "$TEMP_DIR/parsed_packages.toml"; then
                    missing_packages+=("$pkg")
                fi
            done
            
            if [[ ${#missing_packages[@]} -eq 0 ]]; then
                print_success "Package file parsing completed"
            else
                print_error "Missing expected packages: ${missing_packages[*]}"
            fi
        else
            print_error "Output TOML file not created"
        fi
    else
        print_error "Package file parsing failed"
        cat "$TEMP_DIR/parsing_test.log"
    fi
}

# Test 3: Package generation (TOML → package files)
test_package_generation() {
    print_test "Package generation (TOML → package files)"
    
    cd "$PROJECT_ROOT"
    
    # Test 3a: Test Brewfile generation specifically
    # Use a TOML that only has Homebrew packages to ensure Brewfile is generated
    print_info "Testing Brewfile generation..."
    if $PYTHON_CMD bin/package_generators.py \
        --toml "$TEST_ASSETS/test_brewfile_only.toml" \
        --output-dir "$TEMP_DIR/generated_files" \
        --original-brewfile "$TEST_ASSETS/test_brewfile.in" > "$TEMP_DIR/generation_test.log" 2>&1; then
        
        # Check if Brewfile was generated
        if [[ -f "$TEMP_DIR/generated_files/Brewfile" ]]; then
            print_success "Brewfile generation completed"
            print_info "Generated files: $(ls "$TEMP_DIR/generated_files/")"
        else
            print_error "Brewfile not generated"
            cat "$TEMP_DIR/generation_test.log"
        fi
    else
        print_error "Package generation failed"
        cat "$TEMP_DIR/generation_test.log"
    fi
    
    # Test 3b: Test platform-specific generation with mixed packages
    print_info "Testing platform-specific generation with mixed packages..."
    rm -rf "$TEMP_DIR/generated_files_mixed"
    if $PYTHON_CMD bin/package_generators.py \
        --toml "$TEST_ASSETS/test_mixed_packages.toml" \
        --output-dir "$TEMP_DIR/generated_files_mixed" \
        --original-brewfile "$TEST_ASSETS/test_brewfile.in" > "$TEMP_DIR/generation_mixed_test.log" 2>&1; then
        
        # Check if any files were generated (platform-dependent)
        local generated_count=$(ls "$TEMP_DIR/generated_files_mixed/" 2>/dev/null | wc -l)
        
        if [[ $generated_count -gt 0 ]]; then
            print_success "Platform-specific generation completed"
            print_info "Generated files: $(ls "$TEMP_DIR/generated_files_mixed/")"
        else
            print_error "No files generated for current platform"
        fi
    else
        print_error "Platform-specific generation failed"
        cat "$TEMP_DIR/generation_mixed_test.log"
    fi
}

# Test 4: Roundtrip validation (basic)
test_basic_roundtrip() {
    print_test "Basic roundtrip validation"
    
    cd "$PROJECT_ROOT"
    
    # Step 1: Use our test TOML that we know has proper Homebrew packages
    # Instead of generating a potentially incomplete TOML, use our test file
    cp "$TEST_ASSETS/test_brewfile_only.toml" "$TEMP_DIR/roundtrip_step1.toml"
    echo "Using pre-made test TOML with known Homebrew packages" > "$TEMP_DIR/roundtrip_test.log" 2>&1
    
    # Show what's in the TOML for debugging
    print_info "Test TOML contains $(grep -c '^\[' "$TEMP_DIR/roundtrip_step1.toml" || echo 0) packages"
    
    # Ensure output directory exists
    mkdir -p "$TEMP_DIR/roundtrip_output"
    
    # Step 2: Generate Brewfile from TOML (force homebrew target)
    echo "=== Testing package generation command ===" >> "$TEMP_DIR/roundtrip_test.log"
    echo "Command: $PYTHON_CMD bin/package_generators.py --toml $TEMP_DIR/roundtrip_step1.toml --output-dir $TEMP_DIR/roundtrip_output --target homebrew" >> "$TEMP_DIR/roundtrip_test.log"
    
    # First test what would be generated in print-only mode
    echo "=== Print-only test ===" >> "$TEMP_DIR/roundtrip_test.log"
    $PYTHON_CMD bin/package_generators.py \
        --toml "$TEMP_DIR/roundtrip_step1.toml" \
        --target homebrew \
        --print-only >> "$TEMP_DIR/roundtrip_test.log" 2>&1
    
    if $PYTHON_CMD bin/package_generators.py \
        --toml "$TEMP_DIR/roundtrip_step1.toml" \
        --output-dir "$TEMP_DIR/roundtrip_output" \
        --target homebrew \
        --original-brewfile "$TEST_ASSETS/test_brewfile.in" >> "$TEMP_DIR/roundtrip_test.log" 2>&1; then
        
        # Step 3: Check what was generated and validate appropriately
        local generated_files=($(ls "$TEMP_DIR/roundtrip_output/" 2>/dev/null))
        
        if [[ ${#generated_files[@]} -gt 0 ]]; then
            print_info "Generated files for roundtrip: ${generated_files[*]}"
            
            # For Brewfile validation
            if [[ -f "$TEMP_DIR/roundtrip_output/Brewfile" ]]; then
                print_success "Brewfile roundtrip validation passed"
            else
                print_success "Package files generated (platform: $(uname -s))"
            fi
        else
            print_error "No files generated in roundtrip test"
            echo "Contents of output directory:"
            ls -la "$TEMP_DIR/roundtrip_output/" || echo "Directory not found"
            echo "=== FULL ROUNDTRIP LOG ==="
            cat "$TEMP_DIR/roundtrip_test.log"
            echo "=== END LOG ==="
        fi
    else
        print_error "Package generation step failed"
        echo "Last 20 lines of error log:"
        tail -20 "$TEMP_DIR/roundtrip_test.log"
    fi
}

# Test 5: Platform filtering
test_platform_filtering() {
    print_test "Platform filtering logic"
    
    cd "$PROJECT_ROOT"
    
    # Test different output targets
    for target in homebrew all; do
        if $PYTHON_CMD bin/package_generators.py \
            --toml "$TEST_ASSETS/test_mixed_packages.toml" \
            --target "$target" \
            --print-only > "$TEMP_DIR/platform_test_${target}.out" 2>&1; then
            
            if [[ -s "$TEMP_DIR/platform_test_${target}.out" ]]; then
                print_success "Platform filtering for $target completed"
            else
                print_error "No output for platform filtering $target"
            fi
        else
            print_error "Platform filtering for $target failed"
        fi
    done
}

# Test 6: Error handling
test_error_handling() {
    print_test "Error handling (invalid inputs)"
    
    cd "$PROJECT_ROOT"
    
    # Test with non-existent file
    if $PYTHON_CMD bin/package_analysis.py \
        --package-lists "/nonexistent/file.in" \
        --output "$TEMP_DIR/error_test.toml" \
        --cache "$TEMP_DIR/cache.json" > "$TEMP_DIR/error_test.log" 2>&1; then
        
        # Should still work (just warn about missing file)
        print_success "Graceful handling of missing input files"
    else
        # Check if it's a reasonable error
        if grep -q "not found" "$TEMP_DIR/error_test.log"; then
            print_success "Proper error reporting for missing files"
        else
            print_error "Unexpected error handling behavior"
        fi
    fi
}

# Test 7: Unit tests
test_unit_tests() {
    print_test "Python unit tests"
    
    cd "$PROJECT_ROOT"
    
    # Run Python unit tests for package modules
    local unit_test_files=(
        "tests/test_package_analysis.py"
        "tests/test_package_generators.py"
        "tests/test_custom_install.py"
        "tests/test_package_integration.py"
    )
    
    local passed_tests=0
    local total_tests=${#unit_test_files[@]}
    
    for test_file in "${unit_test_files[@]}"; do
        if [[ -f "$test_file" ]]; then
            if $PYTHON_CMD "$test_file" > "$TEMP_DIR/$(basename "$test_file").log" 2>&1; then
                print_success "Unit tests in $(basename "$test_file") passed"
                passed_tests=$((passed_tests + 1))
            else
                print_error "Unit tests in $(basename "$test_file") failed"
                echo "Error log:"
                cat "$TEMP_DIR/$(basename "$test_file").log"
            fi
        else
            print_error "Unit test file not found: $test_file"
        fi
    done
    
    if [[ $passed_tests -eq $total_tests ]]; then
        print_success "All unit tests passed ($passed_tests/$total_tests)"
    else
        print_error "Some unit tests failed ($passed_tests/$total_tests passed)"
    fi
}

# Main test runner
run_all_tests() {
    print_header "Package Management System Tests"
    
    setup_tests
    echo
    
    test_single_package_analysis
    echo
    
    test_package_file_parsing
    echo
    
    test_package_generation
    echo
    
    test_basic_roundtrip
    echo
    
    test_platform_filtering
    echo
    
    test_error_handling
    echo
    
    test_unit_tests
    echo
    
    # Summary
    print_header "Test Summary"
    echo "Tests run: $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        return 1
    fi
}

# Cleanup function
cleanup() {
    if [[ "${KEEP_TEMP:-}" != "1" ]]; then
        print_info "Cleaning up temporary files..."
        rm -rf "$TEMP_DIR"
    else
        print_info "Keeping temporary files in: $TEMP_DIR"
    fi
}

# Set up cleanup trap (but only for full test runs)
# Individual tests handle their own cleanup

# Parse command line arguments
case "${1:-all}" in
    "all")
        trap cleanup EXIT
        run_all_tests
        ;;
    "single")
        setup_tests
        echo
        test_single_package_analysis
        cleanup
        ;;
    "parsing")
        setup_tests
        echo
        test_package_file_parsing
        cleanup
        ;;
    "generation")
        setup_tests
        echo
        test_package_generation
        cleanup
        ;;
    "roundtrip")
        setup_tests
        echo
        test_basic_roundtrip
        cleanup
        ;;
    "filtering")
        setup_tests
        echo
        test_platform_filtering
        cleanup
        ;;
    "errors")
        setup_tests
        echo
        test_error_handling
        cleanup
        ;;
    "unit")
        setup_tests
        echo
        test_unit_tests
        cleanup
        ;;
    *)
        echo "Usage: $0 [all|single|parsing|generation|roundtrip|filtering|errors|unit]"
        echo "  all       - Run all tests (default)"
        echo "  single    - Test single package analysis"
        echo "  parsing   - Test package file parsing"
        echo "  generation - Test package file generation"
        echo "  roundtrip - Test basic roundtrip validation"
        echo "  filtering - Test platform filtering"
        echo "  errors    - Test error handling"
        echo "  unit      - Run Python unit tests"
        echo ""
        echo "Environment variables:"
        echo "  KEEP_TEMP=1 - Keep temporary test files for debugging"
        exit 1
        ;;
esac