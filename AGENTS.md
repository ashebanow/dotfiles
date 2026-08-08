# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a chezmoi-managed dotfiles repository targeting multiple platforms, with primary focus on Bluefin-DX/Bazzite systems. The repository uses a template-driven approach for cross-platform configuration management.

## Key Architecture

### Directory Structure

- `home/` - All dotfiles and configuration templates (chezmoi target root)
- `lib/install/` - Installation scripts (manual-only; not run automatically by chezmoi)
- `lib/common/` - Shared shell functions (platform detection, logging, etc.) used by `lib/install/`

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

Package installation is manual — chezmoi apply no longer triggers it automatically.

```bash
# Bootstrap Homebrew (still automatic, via bootstrap.sh)
./bootstrap.sh

# Run the remaining manual installers (Bitwarden services, etc.)
./install.sh
```

## Installation Script Architecture

### Core Scripts (`lib/install/`)

- `main.sh` - entrypoint called by `install.sh`. Runs the other scripts in this directory in order.
- `prerequisites.sh` - basic system preparation. On the nix-managed hosts (nix-darwin macOS, NixOS servers) all CLI tools come from the nix flake (`modules/features/cli-*.nix` in the lumquat nix-config), so this only fills non-nix Linux gaps and macOS Xcode/Command Line Tools.
- `bitwarden_services.sh` - Bitwarden session management (launchd/systemd/shell fallback)
- `tests/` - unit tests for the install scripts

### Shared Utilities (`lib/common/`)

- `all.sh` - sources the rest of `lib/common/` (platform detection, logging, package-presence checks)
- `logging.sh`, `system_environment.sh`, `packages.sh`

All install scripts source `lib/common/all.sh` and should use its logging/helper functions.

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
- **Waybar**: Status bar for Niri and Hyprland.
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
