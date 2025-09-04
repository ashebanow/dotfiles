# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a chezmoi-managed dotfiles repository targeting multiple platforms, with primary focus on Bluefin-DX/Bazzite systems. The repository uses a template-driven approach for cross-platform configuration management.

## Key Architecture

### Directory Structure

- `home/` - All dotfiles and configuration templates (chezmoi target root)
- `lib/install/` - Installation scripts and automation
- `lib/packaging/` - Package management utilities
- `bin/` - Custom executables and utilities
- `packages/` - All package lists and metadata (Brewfile, Archfile, package_mappings.toml, etc.)

### Platform Support

The system detects and configures for:

- **Linux**: Arch-based (primary), Debian/Ubuntu, Fedora-based immutable
- **macOS**: Darwin platform
- **Windows**: WSL2 environment
- **Containers**: Distrobox integration

### Template System

Uses chezmoi's templating with platform detection:

- `.chezmoi.toml.tmpl` - Main configuration template
- Feature flags: `ephemeral`, `headless`, `personal`, `wsl`
- Platform variables: `arch`, `debian`, `fedora`, `darwin`

### Package Management Organization

All package-related files are organized in the `packages/` directory:

- Package lists: Brewfile, Archfile, Aptfile, Flatfile, etc.
- Metadata: package_mappings.toml, package_name_mappings.json
- Cache: repology_cache.json

## Development Commands

### Python Environment Setup

```bash
# Setup virtual environment (automatic with package commands)
just setup-python

# Manual environment usage
source .venv/bin/activate
python bin/package_analysis.py --help
```

### Chezmoi Operations

```bash
# Apply all changes
chezmoi apply

# Dry run to see what would change
chezmoi diff

# Add new files to chezmoi
chezmoi add ~/.config/newfile

# Edit templates
chezmoi edit ~/.bashrc

# Re-run install script
chezmoi init --apply https://github.com/ashebanow/dotfiles.git
```

### Installation System

```bash
# Bootstrap entire system
curl -sfL https://raw.githubusercontent.com/ashebanow/dotfiles/main/install.sh | bash
```

### Package Management

The repository has a sophisticated multiplatform package management system, found in the `packages/` subdirectory. The input files are the following, depending on the platform:

- `packages/Archfile` - Package list for Arch
- `packages/Aptfile` - Auto-generated Ubuntu equivalents
- `packages/Brewfile.in` - Homebrew packages
- `packages/Brewfile-darwin` - Homebrew packages for mac ONLY. Mostly casks.
- `packages/Flatfile` - Flatpak applications
- `packages/VSExtensionsFile` - VSCode extensions

When modifying packages, update the appropriate file in the `packages/` directory.

## Installation Script Architecture

### Core Scripts (`lib/install/`)

- `install_main.sh` - main entrypoint to the lib/install system, called by install.sh. It
  in turn sources the other files in this directory and calls them in the appropriate order.
- `common/all.sh` - Platform detection, logging, common functions
- `install_prerequisites.sh` - Basic system preparation
- Platform installers: `install_arch.sh`, `install_nix.sh`, `install_homebrew_packages.sh`
- Component installers: `install_fonts.sh`, `install_flatpak_apps.sh`, `install_vscode.sh`

### Installation Flow

1. Platform detection via `all.sh`
2. Prerequisites installation
3. Package manager setup (Homebrew, Nix, etc.)
4. Package installation from lists
5. Component-specific setup (fonts, editors, etc.)

All scripts source `all.sh` for shared functionality and should use its logging functions.

## Package Management System

### Package Override Architecture

The repository follows a "prefer native packages" philosophy, but uses **Homebrew overrides** for critical infrastructure packages that must be consistent across all platforms. Python is managed by UV directly, not through Homebrew.

#### Override Files

- `Brewfile-overrides` - Packages installed via Homebrew on ALL platforms
- Use cases:
  - Critical infrastructure (Python with proper SSL)
  - Cross-platform consistency requirements
  - Dotfiles system dependencies

#### Current Overrides

- **git** - Consistent version for dotfiles management
- **just** - Command runner for package workflows
- **uv** - Fast Python package manager and Python installation manager

#### Installation Flow

1. Install Homebrew override packages first (git, just, uv)
2. Setup Python virtual environment (automatic via `just setup-python`)
   - UV installs and manages Python 3.11 directly
   - Creates isolated environment with `toml` and `requests` libraries
   - No dependency on Homebrew Python
3. Generate platform-specific package lists using virtual environment Python
4. Install platform-appropriate packages

#### Package Files

- `package_mappings.toml` - Master package database with cross-platform mappings (source of truth)
- `Brewfile.in` - Homebrew package template with taps and manual entries
- `tests/assets/legacy_packages/` - Legacy package files used for validation and migration
  - `Archfile`, `Aptfile`, `Flatfile` - Original package lists (legacy source files)
- Generated files: `Brewfile`, `Archfile`, `Aptfile`, `Flatfile` (generated from TOML)

#### Package Management Commands

```bash
# Complete workflow - regenerate and install
just regen-and-generate

# Test specific packages
just add-packages package1 package2

# Clean expired cache
just clean-expired-cache

# Generate package lists only
just generate-package-lists
```

#### Long-Running Command Timeouts

**Important for Claude Code**: When running package analysis or other long-running commands that make API calls, always specify a 10-minute timeout to avoid the default 2-minute timeout:

```bash
# Package analysis - ALWAYS use 10-minute timeout (600000ms)
uv run bin/package_analysis.py --package-lists packages/Brewfile.in --output packages/package_mappings.toml --cache packages/repology_cache.json

# Other long-running commands that may need extended timeout:
# - bin/package_analysis.py (Repology API calls)
# - just regen-toml (calls package_analysis.py)
# - Cache refresh operations
# - Large package list processing
```

The package analysis tool makes many sequential API calls to Repology and can take 3-8 minutes to complete depending on cache state and network conditions.

**Important**: UV manages Python installations directly, ensuring proper SSL compatibility for Repology API access without requiring Homebrew Python.

### ⚠️ CRITICAL: Repology API User-Agent Requirement

**NEVER FORGET**: ALL Repology API calls MUST include a proper User-Agent header with email contact:

```
User-Agent: dotfiles-package-manager/1.0 (ashebanow@cattivi.com)
```

This includes:

- Direct `curl` commands for debugging/testing Repology API
- Any new scripts that query Repology
- Manual API testing during development

**Repology blocks requests without proper User-Agent headers with 403 Forbidden errors.**

The package analysis scripts already include this header, but manual debugging calls often forget it. Use:

```bash
# Correct way to test Repology API
curl -H "User-Agent: dotfiles-package-manager/1.0 (ashebanow@cattivi.com)" "https://repology.org/api/v1/project/package-name"
```

#### Migration Status

**Current State**: Gradual migration to TOML-driven system

- ✅ **TOML as source of truth**: `package_mappings.toml` contains all package metadata
- ✅ **Generated package files**: All package lists are generated from TOML
- ✅ **Legacy files archived**: Original package files moved to `tests/assets/legacy_packages/`
- ⏳ **Validation phase**: Legacy files used for comparison and testing
- 🚀 **Future cleanup**: Legacy analysis code can be removed after validation period

The system now generates all package files from the TOML, with legacy files kept for validation purposes.

### Priority System

The package management system uses a **semantic priority system** in `package_mappings.toml` to control package installation behavior:

#### Priority Values

- **`None` (default)** - Empty/unset priority for regular packages that follow normal platform preferences
- **`"override"`** - Marks packages for Homebrew installation on ALL platforms, bypassing native package managers

#### Automated Override Generation

The system automatically generates `Brewfile-overrides` content from packages with `priority = "override"`:

```toml
# Example TOML entries with override priority
[git]
priority = "override"
description = "Git version control system"

[python@3.11]
priority = "override"
description = "Python 3.11 with proper OpenSSL (essential for package analysis)"
```

#### When to Use Override Priority

Use `priority = "override"` for packages that must be installed via Homebrew on all platforms:

- **Critical infrastructure** packages needed by the dotfiles system itself
- **Cross-platform consistency** requirements where version differences matter
- **Compatibility fixes** where Homebrew version has essential features missing from native packages

#### Implementation Details

- Package analysis defaults to `priority = None` for new packages
- Package generators automatically detect `priority = "override"` and add to Brewfile
- Manual `Brewfile-overrides` file serves as fallback/additional entries
- Override packages are processed first during installation

This replaces the previous arbitrary "high/medium/low" priority system with semantic meaning that drives actual behavior.

### Automated Cache Refresh

A GitHub Action runs daily to refresh 1/7 of the package cache:

- **Age-based refresh**: Selects the oldest ~1/7 of cache entries for refresh
- Runs daily, refreshing approximately 40 packages (for ~280 total packages)
- Ensures all entries are refreshed at least weekly
- Prioritizes stalest data for optimal cache freshness
- Automatically commits updates like dependabot

#### Cache Management Commands

```bash
# Show cache statistics and refresh strategy
just cache-stats

# Clean expired entries manually
just clean-expired-cache

# Refresh specific segment (GitHub Action creates this script)
just refresh-cache-segment 0
```

## Configuration Areas

### Development Environment

- **Zed**: Modern editor config in `home/dot_config/zed/`
- **Neovim**: Lua-based config in `home/dot_config/nvim/`
- **VS Code**: JSON configs with templating in `home/dot_config/Code/User/`

### Shell Environment

- **Fish/Zsh**: Configs with shared aliases and functions
- **Starship**: Cross-shell prompt configuration
- **CLI tools**: bat, eza, fzf, ripgrep with consistent theming

### Desktop (Linux)

- **Hyprland**: Preferred Window Manager.
- **Niri**: An alternatve Window Manager.
- **Gnome**: Development Environment preinstalled on many distros. Kept as a fallback in case
  Hyprland or Niri breaks.
- **HyprPanel**: Status bar for Hyprland
- **Waybar**: Status bar for Niri. Can also be enabled for Hyprland if HyprPanel breaks.
- **Font management**: Nerd Fonts installation and configuration, using `getnf`.

## Secrets Management

Uses Bitwarden CLI integration for sensitive data:

- SSH keys and Git credentials
- API tokens and personal information
- Template functions: `bitwarden`, `bitwardenFields`

Never commit secrets directly - always use chezmoi templating with Bitwarden.

## Testing Installation Changes

TODO: All mini-scripts like this should really be in a Justfile.

1. Test platform detection:

   ```bash
   source lib/common/all.sh
   echo "Platform: $PLATFORM, Distro: $DISTRO"
   ```

2. Use distrobox for testing different environments:

   ```bash
   distrobox create --name test-arch --image archlinux:latest
   distrobox enter test-arch
   ```

3. Dry-run chezmoi changes:
   ```bash
   chezmoi diff
   ```

## Common Patterns

### Adding New Packages

1. Add to appropriate package file (Archfile for primary)
2. Update installation scripts if needed
3. Test on target platforms

### Template Modifications

1. Edit source files with `chezmoi edit`
2. Use `chezmoi diff` to preview changes
3. Apply with `chezmoi apply`

### Platform-Specific Configuration

Use chezmoi conditionals in templates:

```
{{- if eq .chezmoi.os "darwin" }}
# macOS specific config
{{- else if .debian }}
# Debian specific config
{{- end }}
```

## Branch Strategy

- `main` - Stable configuration
- `gum` - Current development branch
- Feature branches for major changes

Always test changes on development systems before merging to main.
