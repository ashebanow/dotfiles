# Tagging System Examples and Use Cases

This document provides practical examples of how to use the tag-based package filtering system.

## Basic Tag Queries

### Platform-Specific Filtering
```bash
# Generate packages for macOS only
bin/package_generators_tagged.py --query "os:macos" --toml packages/package_mappings.toml

# Generate packages for Linux distributions with APT
bin/package_generators_tagged.py --query "os:linux AND pm:apt" --toml packages/package_mappings.toml

# Generate packages for Arch-like distributions
bin/package_generators_tagged.py --query "dist:arch" --toml packages/package_mappings.toml
```

### Category-Based Installation
```bash
# Install only development tools
bin/package_generators_tagged.py --query "cat:development" --toml packages/package_mappings.toml

# Install multimedia and graphics packages
bin/package_generators_tagged.py --query "cat:multimedia OR cat:graphics" --toml packages/package_mappings.toml

# Install essential tools only
bin/package_generators_tagged.py --query "priority:essential" --toml packages/package_mappings.toml
```

### Desktop Environment-Based Installation
```bash
# Install GNOME-specific packages
bin/package_generators_tagged.py --desktop-environment gnome --toml packages/package_mappings.toml

# Install Hyprland-specific packages
bin/package_generators_tagged.py --de hyprland --toml packages/package_mappings.toml

# Install packages excluding specific desktop environments
bin/package_generators_tagged.py --exclude-de gnome kde --toml packages/package_mappings.toml

# Install packages for KDE but not GNOME (using query syntax)
bin/package_generators_tagged.py --query "de:kde AND NOT de:gnome" --toml packages/package_mappings.toml
```

### Atomic/Immutable Distribution Support
```bash
# Generate packages optimized for atomic distributions (Bazzite, Silverblue, etc.)
bin/package_generators_tagged.py --atomic-distro --toml packages/package_mappings.toml

# Generate packages for traditional mutable distributions  
bin/package_generators_tagged.py --traditional-distro --toml packages/package_mappings.toml

# Homebrew and Flatpak only (safe for atomic distros)
bin/package_generators_tagged.py --query "pm:homebrew OR pm:flatpak" --toml packages/package_mappings.toml

# Exclude packages that require system package layering
bin/package_generators_tagged.py --query "NOT (pm:dnf OR pm:apt OR pm:pacman)" --toml packages/package_mappings.toml
```

## Machine Role Examples

### Development Workstation
```bash
# Generate packages for a development machine
bin/package_generators_tagged.py --role development --toml packages/package_mappings.toml
```

**Includes packages tagged with:**
- `role:development`
- `cat:development`, `cat:editor`, `cat:vcs`
- `priority:essential` and `priority:recommended`

### Desktop Environment
```bash
# Generate packages for desktop/GUI usage
bin/package_generators_tagged.py --role desktop --toml packages/package_mappings.toml
```

**Includes packages tagged with:**
- `role:desktop`
- `cat:gui`, `cat:browser`, `cat:multimedia`
- `cat:cask` (macOS applications)

### Headless Server
```bash
# Generate packages for server deployment
bin/package_generators_tagged.py --role server --toml packages/package_mappings.toml
```

**Includes packages tagged with:**
- `role:server`, `role:headless`
- `cat:system`, `cat:network`, `cat:security`
- Excludes `cat:gui`, `cat:cask`

## Complex Query Examples

### Secure Development Environment
```bash
# Security-focused development setup
bin/package_generators_tagged.py --query "(cat:development OR cat:security) AND priority:essential" --toml packages/package_mappings.toml
```

### Minimal Installation
```bash
# Only core essential packages
bin/package_generators_tagged.py --query "scope:core AND priority:essential" --toml packages/package_mappings.toml
```

### Cross-Platform Compatible Only
```bash
# Packages that work on both macOS and Linux
bin/package_generators_tagged.py --query "(os:macos AND os:linux) OR pm:homebrew" --toml packages/package_mappings.toml
```

### Exclude Specific Categories
```bash
# All packages except gaming and multimedia
bin/package_generators_tagged.py --query "NOT (cat:gaming OR cat:multimedia)" --toml packages/package_mappings.toml
```

## Package Entry Examples

### Development Tool with Multiple Platforms
```toml
[git]
tags = [
    "os:macos", "os:linux",
    "pm:homebrew", "pm:apt", "pm:pacman",
    "cat:development", "cat:vcs",
    "role:development",
    "priority:essential", "scope:core"
]
description = "Distributed version control system"
```

### macOS-Specific GUI Application
```toml
[visual-studio-code]
tags = [
    "os:macos",
    "pm:homebrew:darwin", "cat:cask",
    "cat:development", "cat:editor", "cat:gui",
    "role:development", "role:desktop",
    "priority:recommended"
]
description = "Visual Studio Code editor"
brew-is-cask = true
```

### Cross-Platform with Fallback
```toml
[ripgrep]
tags = [
    "os:macos", "os:linux",
    "pm:homebrew", "pm:apt", "pm:pacman", "pm:custom",
    "cat:cli-tool", "cat:development",
    "role:development",
    "priority:recommended"
]
description = "Fast grep alternative"
custom-install = {
    default = ["cargo install ripgrep"]
}
custom-install-priority = "fallback"
```

### Server-Specific Tool
```toml
[nginx]
tags = [
    "os:linux",
    "pm:apt", "pm:pacman", "pm:dnf",
    "cat:server", "cat:network",
    "role:server", "role:headless",
    "priority:optional"
]
description = "HTTP server and reverse proxy"
```

### Desktop Environment-Specific Packages
```toml
[gnome-shell]
tags = [
    "os:linux",
    "de:gnome",
    "cat:desktop-environment",
    "role:desktop",
    "priority:essential"
]
description = "GNOME desktop shell"

[hyprland]
tags = [
    "os:linux",
    "de:hyprland",
    "cat:desktop-environment", "cat:wayland",
    "role:desktop",
    "priority:recommended"
]
description = "Dynamic tiling Wayland compositor"

[i3-wm]
tags = [
    "os:linux",
    "de:i3",
    "cat:desktop-environment", "cat:tiling",
    "role:desktop",
    "priority:recommended"
]
description = "Improved tiling window manager"
```

### Atomic Distribution-Aware Packages
```toml
[development-tools]
tags = [
    "os:linux",
    "pm:homebrew", "pm:flatpak",  # Safe for atomic distros
    "cat:development",
    "role:development",
    "priority:recommended"
]
description = "Development tools via container-safe package managers"

[system-package]
tags = [
    "os:linux",
    "pm:dnf", "pm:apt",  # Requires package layering
    "disttype:traditional",  # Only for traditional distros
    "cat:system",
    "priority:optional"
]
description = "System package requiring native package manager"
```

## Migration Examples

### Converting Legacy Package Entry
```bash
# Before migration (legacy format)
[example-package]
arch-pkg = "example"
apt-pkg = "example"
brew-supports-darwin = true
brew-supports-linux = false
description = "Example package"

# After migration using tag_migration.py
bin/tag_migration.py --package example-package --toml packages/package_mappings.toml

# Result:
[example-package]
tags = [
    "os:linux", "os:macos",
    "pm:pacman", "pm:apt", "pm:homebrew:darwin",
    "cat:utility",  # auto-categorized
    "priority:recommended"  # auto-assigned
]
description = "Example package"
```

## Use Case Scenarios

### 1. New Machine Setup
```bash
# Step 1: Essential tools first
bin/package_generators_tagged.py --query "priority:essential" --output-dir /tmp/setup

# Step 2: Role-specific packages
bin/package_generators_tagged.py --role development --output-dir /tmp/setup

# Step 3: Platform-specific GUI apps (if desktop)
bin/package_generators_tagged.py --query "role:desktop AND cat:gui" --output-dir /tmp/setup
```

### 2. Docker Container Package Lists
```bash
# Minimal container with development tools
bin/package_generators_tagged.py --query "role:headless AND cat:development AND priority:essential" --output-dir docker/dev

# Data science container
bin/package_generators_tagged.py --query "role:data-science AND (priority:essential OR priority:recommended)" --output-dir docker/datascience
```

### 3. CI/CD Environment
```bash
# Build environment packages
bin/package_generators_tagged.py --query "role:devops AND cat:development AND scope:core" --output-dir ci/build

# Testing environment packages  
bin/package_generators_tagged.py --query "cat:development AND cat:testing" --output-dir ci/test
```

### 4. Custom Package Sets
```bash
# Security audit toolkit
bin/package_generators_tagged.py --query "cat:security OR (cat:network AND cat:analysis)" --output-dir security-toolkit

# Content creation setup
bin/package_generators_tagged.py --query "role:content-creation OR cat:multimedia OR cat:graphics" --output-dir content-creation
```

### 5. Desktop Environment Scenarios
```bash
# Hyprland workstation setup
bin/package_generators_tagged.py --query "(de:hyprland OR role:desktop) AND NOT (de:gnome OR de:kde)" --output-dir hyprland-setup

# GNOME-only packages for a clean GNOME installation
bin/package_generators_tagged.py --de gnome --output-dir gnome-only

# Tiling window manager essentials (i3, sway, hyprland)
bin/package_generators_tagged.py --query "de:i3 OR de:sway OR de:hyprland OR cat:tiling" --output-dir tiling-wm

# Everything except desktop environment packages (headless server)
bin/package_generators_tagged.py --query "NOT (de:gnome OR de:kde OR de:xfce OR de:hyprland OR de:sway OR de:i3)" --output-dir headless
```

### 6. Atomic Distribution Scenarios
```bash
# Bazzite gaming setup (atomic + gaming focus)
bin/package_generators_tagged.py --query "disttype:atomic AND (role:gaming OR cat:gaming OR pm:flatpak)" --output-dir bazzite-gaming

# Silverblue development workstation (atomic + development)
bin/package_generators_tagged.py --query "(pm:homebrew OR pm:flatpak OR pm:custom) AND cat:development" --output-dir silverblue-dev

# Universal Blue distro setup (container-safe packages only)
bin/package_generators_tagged.py --atomic-distro --output-dir universal-blue

# Fedora Atomic with Hyprland DE
bin/package_generators_tagged.py --query "de:hyprland AND (pm:homebrew OR pm:flatpak)" --output-dir atomic-hyprland
```

## Maintenance Commands

### Analyze Current Package Distribution
```bash
# Show tag distribution across all packages
bin/package_generators_tagged.py --analyze --toml packages/package_mappings.toml

# List all available tags
bin/package_generators_tagged.py --list-tags --toml packages/package_mappings.toml
```

### Migrate Legacy Packages
```bash
# Migrate all packages to tagged format
bin/tag_migration.py --migrate-all --toml packages/package_mappings.toml --dry-run

# Apply migration after review
bin/tag_migration.py --migrate-all --toml packages/package_mappings.toml
```

### Auto-Tag New Packages
```bash
# Generate tags for new packages using analysis
bin/package_analysis_tagged.py --enhance-tags --toml packages/package_mappings.toml
```

## Best Practices

1. **Use hierarchical tags**: `pm:homebrew` matches both `pm:homebrew:darwin` and `pm:homebrew:linux`
2. **Combine role and category tags**: Packages should have both functional (`cat:development`) and contextual (`role:desktop`) tags
3. **Set appropriate priorities**: Use `priority:essential` sparingly for truly critical tools
4. **Test queries**: Use `--print-only` to preview generated files before writing
5. **Document custom tags**: Add comments explaining non-standard tags in your TOML file

## Integration with Dotfiles

The tagging system integrates seamlessly with your existing dotfiles workflow:

```bash
# In your dotfiles setup script
bin/package_generators_tagged.py --role development --output-dir packages/generated
brew bundle --file=packages/generated/Brewfile
```

This approach allows for flexible, role-based package management while maintaining compatibility with existing package management tools.