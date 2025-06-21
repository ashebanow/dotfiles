# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a chezmoi-managed dotfiles repository targeting multiple platforms, with primary focus on Bluefin-DX/Bazzite systems. The repository uses a template-driven approach for cross-platform configuration management.

## Key Architecture

### Directory Structure
- `home/` - All dotfiles and configuration templates (chezmoi target root)
- `lib/install/` - Installation scripts and automation
- `bin/` - Custom executables and utilities
- Package files at root (Archfile, Brewfile, Aptfile, etc.) - Platform-specific package lists

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

## Development Commands

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
The repository maintains synchronized package lists:
- `Archfile` (175 packages) - Primary package list for Arch
- `Aptfile` - Auto-generated Ubuntu equivalents
- `Brewfile` - Homebrew packages
- `Flatfile` - Flatpak applications

When modifying packages, update the appropriate file for the target platform.

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
