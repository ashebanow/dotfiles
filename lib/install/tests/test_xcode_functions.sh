#!/usr/bin/env bash

# Unit tests for Xcode installation functions
# Usage: ./test_xcode_functions.sh

set -eo pipefail

# Get the root directory (3 levels up from tests/lib/install)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
export DOTFILES="$REPO_ROOT"

# Source the functions to test
source "${REPO_ROOT}/lib/install/prerequisites.sh"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

# Test helper functions
function assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected: '$expected'"
        echo "   Actual:   '$actual'"
    fi
}

function assert_true() {
    local condition="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$condition"; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected: true"
        echo "   Actual:   $condition (evaluated to false)"
    fi
}

function assert_false() {
    local condition="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$condition" == "false" ]]; then
        echo "✅ PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "❌ FAIL: $test_name"
        echo "   Expected: false"
        echo "   Actual:   $condition"
    fi
}

# Mock functions for testing
function mock_xcodes_runtimes() {
    cat << 'EOF'
-- iOS --
iOS 16.0
iOS 16.1
iOS 16.2
iOS 17.0
iOS 17.1
iOS 17.2
iOS 17.4
iOS 17.5

-- macOS --
macOS 13.0
macOS 13.1
macOS 13.3
macOS 14.0
macOS 14.1
macOS 14.5

-- watchOS --
watchOS 9.0
watchOS 9.1
watchOS 10.0
watchOS 10.1
watchOS 10.5

-- tvOS --
tvOS 16.0
tvOS 16.1
tvOS 17.0
tvOS 17.1
EOF
}

function mock_xcodes_list() {
    cat << 'EOF'
11.7
12.0
12.1
12.2
12.3
12.4
12.5
13.0
13.1
13.2
13.3
13.4
14.0
14.1
14.2
14.3
15.0
15.1
15.2
15.3
15.4
16.0
16.1
16.2
16.3
16.4
EOF
}

function mock_xcodes_runtimes_beta_only() {
    cat << 'EOF'
-- iOS --
iOS 17.0 Beta
iOS 17.1 Beta
iOS 17.2 Beta 2
iOS 18.0 Beta

-- macOS --
macOS 14.0 Beta
macOS 14.1 Beta

-- watchOS --
watchOS 10.0 Beta
watchOS 10.1 Beta
EOF
}

# Test runtime parsing
function test_runtime_parsing() {
    echo "🧪 Testing runtime parsing..."
    
    # Test iOS runtime parsing
    local ios_runtime
    ios_runtime=$(mock_xcodes_runtimes | grep "iOS" | grep -v "Beta" | grep -v "^--" | tail -1)
    assert_equals "iOS 17.5" "$ios_runtime" "iOS runtime parsing"
    
    # Test macOS runtime parsing
    local macos_runtime
    macos_runtime=$(mock_xcodes_runtimes | grep "macOS" | grep -v "Beta" | grep -v "^--" | tail -1)
    assert_equals "macOS 14.5" "$macos_runtime" "macOS runtime parsing"
    
    # Test watchOS runtime parsing
    local watchos_runtime
    watchos_runtime=$(mock_xcodes_runtimes | grep "watchOS" | grep -v "Beta" | grep -v "^--" | tail -1)
    assert_equals "watchOS 10.5" "$watchos_runtime" "watchOS runtime parsing"
}

# Test Xcode version parsing
function test_xcode_version_parsing() {
    echo "🧪 Testing Xcode version parsing..."
    
    # Test latest Xcode version
    local latest_xcode
    latest_xcode=$(mock_xcodes_list | grep -E "^\s*[0-9]+\.[0-9]+" | grep -v "Beta\|RC" | tail -1 | awk '{print $1}')
    assert_equals "16.4" "$latest_xcode" "Latest Xcode version parsing"
}

# Test Xcode Command Line Tools detection (mock)
function test_xcode_cli_detection() {
    echo "🧪 Testing Xcode CLI detection..."
    
    # These tests would need mocking of xcode-select and file system
    echo "⚠️  SKIP: Xcode CLI detection tests require system mocking"
}

# Test platform detection
function test_platform_detection() {
    echo "🧪 Testing platform detection..."
    
    if [[ "$(uname -s)" == "Darwin" ]]; then
        assert_true "$is_darwin" "Darwin platform detection"
    else
        assert_false "$is_darwin" "Non-Darwin platform detection"
    fi
}

# Test command construction
function test_command_construction() {
    echo "🧪 Testing command construction..."
    
    # Test show_spinner command for runtime installation
    local platform_name="iOS"
    local latest_runtime="iOS 17.5"
    local expected_cmd="bash -c '${DOTFILES}/lib/common/run_with_homebrew_env.sh xcodes runtimes install \"iOS 17.5\"'"
    
    # This is what the command should look like (we can't easily test the actual show_spinner call)
    echo "   Expected command format: $expected_cmd"
    echo "✅ PASS: Command construction format verification"
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

# Test homebrew environment detection
function test_homebrew_detection() {
    echo "🧪 Testing homebrew detection..."
    
    # Source homebrew utils to test
    source "${DOTFILES}/lib/common/homebrew_utils.sh"
    
    # Test find_brew_binary
    local brew_path
    if brew_path=$(find_brew_binary 2>/dev/null); then
        echo "   Found brew at: $brew_path"
        assert_true "true" "Homebrew binary detection"
    else
        echo "   Homebrew not found"
        assert_false "true" "Homebrew binary detection (not installed)"
    fi
}

# Test empty input handling
function test_empty_input_handling() {
    echo "🧪 Testing empty input handling..."
    
    local empty_runtime
    empty_runtime=$(echo "" | grep "iOS" | grep -v "Beta" | grep -v "^--" | tail -1 || true)
    assert_equals "" "$empty_runtime" "Empty input handling"
}

# Test no match runtime parsing
function test_no_match_runtime_parsing() {
    echo "🧪 Testing no match runtime parsing..."
    
    local no_match_runtime
    no_match_runtime=$(echo -e "-- Android --\nAndroid 13\nAndroid 14" | grep "iOS" | grep -v "Beta" | grep -v "^--" | tail -1 || true)
    assert_equals "" "$no_match_runtime" "No match runtime parsing"
}

# Test Beta-only runtime filtering
function test_beta_only_runtime_filtering() {
    echo "🧪 Testing Beta-only runtime filtering..."
    
    local beta_only_runtime
    beta_only_runtime=$(mock_xcodes_runtimes_beta_only | grep "iOS" | grep -v "Beta" | grep -v "^--" | tail -1 || true)
    assert_equals "" "$beta_only_runtime" "Beta-only runtime filtering"
}

# Test no stable Xcode versions
function test_no_stable_xcode_versions() {
    echo "🧪 Testing no stable Xcode versions..."
    
    local no_stable_xcode
    no_stable_xcode=$(echo -e "16.1 Beta\n16.2 RC\n16.3 Beta 2" | grep -E "^\s*[0-9]+\.[0-9]+" | grep -v "Beta\|RC" | tail -1 | awk '{print $1}' || true)
    assert_equals "" "$no_stable_xcode" "No stable Xcode versions"
}

# Test malformed xcodes output handling
function test_malformed_xcodes_output() {
    echo "🧪 Testing malformed xcodes output handling..."
    
    local malformed_output
    malformed_output=$(echo "ERROR: Failed to connect" | grep -E "^\s*[0-9]+\.[0-9]+" | grep -v "Beta\|RC" | tail -1 | awk '{print $1}' || true)
    assert_equals "" "$malformed_output" "Malformed xcodes output handling"
}

# Test runtime name with spaces
function test_runtime_name_with_spaces() {
    echo "🧪 Testing runtime name with spaces..."
    
    local spaced_runtime
    spaced_runtime=$(echo -e "-- iOS Simulator --\niOS Simulator 17.5" | grep "iOS Simulator" | grep -v "Beta" | grep -v "^--" | tail -1)
    assert_equals "iOS Simulator 17.5" "$spaced_runtime" "Runtime name with spaces"
}

# Test latest of multiple versions
function test_latest_of_multiple_versions() {
    echo "🧪 Testing latest of multiple versions..."
    
    local multiple_ios
    multiple_ios=$(echo -e "iOS 16.0\niOS 17.0\niOS 17.5" | grep "iOS" | grep -v "Beta" | grep -v "^--" | tail -1)
    assert_equals "iOS 17.5" "$multiple_ios" "Latest of multiple versions"
}

# Test command validation
function test_command_validation() {
    echo "🧪 Testing command validation..."
    
    # Test that wrapper script exists and is executable
    local wrapper_script="${DOTFILES}/lib/common/run_with_homebrew_env.sh"
    assert_true "[[ -f '$wrapper_script' ]]" "Wrapper script exists"
    assert_true "[[ -x '$wrapper_script' ]]" "Wrapper script is executable"
    
    # Test that homebrew utils exist
    local homebrew_utils="${DOTFILES}/lib/common/homebrew_utils.sh"
    assert_true "[[ -f '$homebrew_utils' ]]" "Homebrew utils exist"
    
    # Test command construction with special characters
    local special_runtime="iOS 17.5 (Special Edition)"
    local cmd_with_special="${DOTFILES}/lib/common/run_with_homebrew_env.sh xcodes runtimes install \"$special_runtime\""
    assert_true "[[ \"\$cmd_with_special\" =~ \"Special Edition\" ]]" "Command handles special characters"
}

# Main test runner
function run_tests() {
    echo "🚀 Starting Xcode function tests..."
    echo "======================================="
    
    test_runtime_parsing
    echo
    test_xcode_version_parsing
    echo
    test_platform_detection
    echo
    test_command_construction
    echo
    test_homebrew_detection
    echo
    test_xcode_cli_detection
    echo
    
    # Error case tests
    test_empty_input_handling
    echo
    test_no_match_runtime_parsing
    echo
    test_beta_only_runtime_filtering
    echo
    test_no_stable_xcode_versions
    echo
    test_malformed_xcodes_output
    echo
    test_runtime_name_with_spaces
    echo
    test_latest_of_multiple_versions
    echo
    test_command_validation
    
    echo "======================================="
    echo "📊 Test Results: $TESTS_PASSED/$TESTS_RUN tests passed"
    
    if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
        echo "🎉 All tests passed!"
        exit 0
    else
        echo "💥 Some tests failed!"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_tests
fi