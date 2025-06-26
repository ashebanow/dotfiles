# Testing Infrastructure

This directory contains test scripts and assets for the dotfiles repository.

## Package Management Tests

### Running Tests

Use the justfile commands for the easiest experience:

```bash
# Run all package management tests
just test-packages

# Run specific test category
just test-packages-specific single
just test-packages-specific roundtrip
just test-packages-specific generation

# Run all tests (package + install scripts)
just test-all
```

### Manual Test Execution

```bash
# Run all package management tests
./tests/test_package_management.sh all

# Run specific test
./tests/test_package_management.sh single
./tests/test_package_management.sh parsing
./tests/test_package_management.sh generation
./tests/test_package_management.sh roundtrip
./tests/test_package_management.sh filtering
./tests/test_package_management.sh errors
```

### Test Categories

- **single**: Single package analysis (`--package bat gh zellij`)
- **parsing**: Package file parsing (Brewfile.in, Archfile, etc.)
- **generation**: TOML → package file generation
- **roundtrip**: Full roundtrip validation (packages → TOML → packages)
- **filtering**: Platform-specific filtering logic
- **errors**: Error handling and edge cases

### Test Assets

Test files are located in `tests/assets/package_mapping/`:

- `test_brewfile.in` - Simple Brewfile for testing
- `simple_archfile` - Arch package list
- `simple_aptfile` - Apt package list  
- `simple_flatfile` - Flatpak package list
- `test_mixed_packages.toml` - Example TOML with mixed platforms

### Environment Variables

- `KEEP_TEMP=1` - Keep temporary test files for debugging

## Install Script Tests

Currently no install script tests are implemented. To add them:

1. Create `tests/test_install.sh` for comprehensive install testing
2. Or create individual test files in `lib/install/tests/`

Example test structure:
```bash
tests/test_install.sh
lib/install/tests/
├── test_platform_detection.sh
├── test_package_installation.sh
└── test_common_functions.sh
```

## Development Workflow

### Adding New Package Tests

1. Add test assets to `tests/assets/package_mapping/`
2. Update `test_package_management.sh` with new test functions
3. Add justfile commands if needed
4. Run tests: `just test-packages`

### Debugging Package Issues

```bash
# Debug specific package
just debug-package zellij

# Show current mapping
just show-package zellij

# Run targeted test
just test-packages-specific single
```

### Adding New Tools/Packages

```bash
# Add packages for analysis
just add-packages neovim zed

# Regenerate complete TOML
just regen-toml

# Validate the changes
just validate-roundtrip
```