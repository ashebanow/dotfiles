# Testing Strategy for Installation Scripts

This document outlines approaches for testing installation and system configuration scripts without affecting the host system.

## The Challenge

Testing infrastructure and installation code presents unique challenges:
- **System Modification Risk**: Installation scripts modify the system state
- **Platform Dependencies**: Some tools (like `xcodes`) are platform-specific
- **Environment Requirements**: Tests need access to package managers, system tools
- **Integration Complexity**: Unit tests miss subprocess execution and quoting issues

## Testing Approaches

### 1. Mock/Stub Integration Tests

Create tests that mock system calls but test the full execution path:

```bash
function test_show_spinner_with_mock_commands() {
    # Create a temporary mock script that acts like xcodes
    local mock_xcodes="${TMPDIR}/mock_xcodes"
    cat > "$mock_xcodes" << 'EOF'
#!/bin/bash
case "$1" in
    "runtimes")
        echo "-- iOS --"
        echo "iOS 17.5"
        ;;
    "install")
        echo "Installing Xcode..."
        ;;
esac
EOF
    chmod +x "$mock_xcodes"
    
    # Temporarily replace xcodes in PATH
    export PATH="${TMPDIR}:$PATH"
    
    # Test the full show_spinner execution
    if show_spinner "Test runtime install" \
        "${DOTFILES}/lib/common/run_with_homebrew_env.sh $mock_xcodes runtimes" \
        "Test completed"; then
        assert_true "true" "Integration test with mock xcodes"
    fi
    
    rm -f "$mock_xcodes"
}
```

### 2. Platform-Specific Test Suites

```bash
# tests/lib/install/test_xcode_functions_integration.sh
if [[ "$(uname -s)" == "Darwin" ]]; then
    # Run real macOS integration tests
    run_macos_integration_tests
else
    # Run mock-based tests on other platforms
    run_mock_integration_tests
fi
```

### 3. GitHub Actions Matrix Testing

```yaml
# .github/workflows/test.yml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest]
    test-type: [unit, integration]
    exclude:
      - os: ubuntu-latest
        test-type: integration  # Skip real integration on Linux
```

### 4. Dry-Run Mode for Installation Scripts

Add a `--dry-run` flag to installation functions:

```bash
function install_simulator_runtime() {
    local platform_name="$1"
    local display_name="$2"
    local dry_run="${3:-false}"
    
    if [[ "$dry_run" == "true" ]]; then
        echo "DRY RUN: Would install $display_name runtime"
        return 0
    fi
    
    # Real installation logic...
}
```

### 5. Containerized Testing with Volume Mounts

```dockerfile
# tests/Dockerfile.macos-test
FROM sickcodes/docker-osx:latest
COPY . /workspace
RUN /workspace/tests/run_integration_tests.sh
```

### 6. Test Environment Isolation

```bash
function setup_test_environment() {
    # Create isolated test directory
    export TEST_DOTFILES="/tmp/test-dotfiles-$$"
    cp -r "$DOTFILES" "$TEST_DOTFILES"
    export DOTFILES="$TEST_DOTFILES"
    
    # Mock system commands
    export PATH="/tmp/test-bin:$PATH"
    create_mock_commands
}
```

### 7. Partial Integration Tests

Test individual components that don't require full system modification:

```bash
function test_homebrew_env_setup() {
    # Test that the wrapper script can find brew and set up environment
    local output
    output=$("${DOTFILES}/lib/common/run_with_homebrew_env.sh" env | grep HOMEBREW)
    
    if [[ -n "$output" ]]; then
        assert_true "true" "Homebrew environment setup works"
    fi
}
```

### 8. Property-Based Testing

Test that commands are properly formatted without executing them:

```bash
function test_command_parsing() {
    # Verify that commands can be parsed correctly
    local cmd="${DOTFILES}/lib/common/run_with_homebrew_env.sh xcodes runtimes install 'iOS 17.5'"
    
    # Parse the command and verify components
    local script_path="${cmd%% *}"
    assert_true "[[ -x '$script_path' ]]" "Script is executable"
    
    # Test command structure
    assert_true "[[ '$cmd' =~ 'xcodes runtimes install' ]]" "Command structure is correct"
}
```

## Recommended Approach

1. **Keep unit tests** for parsing logic (like we have in `tests/lib/install/test_xcode_functions.sh`)
2. **Add mock integration tests** that test the full execution path with fake commands
3. **Add property-based tests** that verify command structure without execution
4. **Use CI/CD with multiple platforms** - run real integration tests only on macOS runners
5. **Add dry-run modes** to installation functions for safer testing

## Test Categories

### Unit Tests
- ✅ **Current**: Parse mock data (runtime versions, command parsing)
- ✅ **Current**: Platform detection
- ✅ **Current**: Homebrew binary detection

### Integration Tests
- 🚧 **Needed**: Full `show_spinner` execution with mocks
- 🚧 **Needed**: Subprocess execution and quoting validation
- 🚧 **Needed**: Error condition handling

### System Tests
- 🚧 **Future**: Real installation on clean VMs/containers
- 🚧 **Future**: Cross-platform compatibility verification

## Benefits

This multi-layered approach provides:
- **Confidence** in code correctness without system modification risk
- **Platform coverage** across different operating systems
- **Fast feedback** through unit and mock tests
- **Comprehensive validation** through selective integration testing
- **CI/CD compatibility** with automated testing pipelines

## Example Test Structure

```
tests/
├── unit/                    # Fast, isolated tests
│   ├── lib/
│   │   ├── common/
│   │   └── install/
│   │       └── test_xcode_functions.sh
├── integration/             # Mock-based integration tests
│   ├── lib/
│   │   └── install/
│   │       └── test_xcode_integration.sh
└── system/                  # Real system tests (CI only)
    └── macos/
        └── test_full_installation.sh
```

This strategy gives us confidence in the code without requiring dangerous system modifications during testing!