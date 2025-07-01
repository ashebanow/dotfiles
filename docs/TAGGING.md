# Package Tagging System

## Overview

The package tagging system provides a flexible and extensible way to categorize and filter packages based on platform support, software categories, machine roles, and installation priorities. This system replaces the previous boolean platform flags with a rich, multi-dimensional tagging approach.

## Design Principles

1. **Namespace Organization**: Tags use namespace prefixes to organize different dimensions
2. **Backward Compatibility**: Existing platform detection continues to work during migration
3. **Query Flexibility**: Support for complex boolean operations on tag sets
4. **Future-Proof**: Easy addition of new platforms, categories, and roles
5. **Machine-Role Targeting**: Enable precise package selection for different use cases

## Important Notes on Tag Usage

### Arbitrary Tags
- **Users can add arbitrary tags** to any package entry
- **Only predefined namespace prefixes** (`os:`, `arch:`, `dist:`, `disttype:`, `de:`, `pm:`, `cat:`, `role:`, `priority:`, `scope:`) are recognized by the filtering system
- **Custom tags without recognized prefixes** will be stored but ignored by the installation infrastructure
- **User-defined namespace prefixes** are not supported - they will be treated as plain string tags

### Examples:
```toml
[package-name]
tags = [
    "os:linux",           # ✓ Recognized: OS namespace
    "cat:development",    # ✓ Recognized: Category namespace
    "my-custom-tag",      # ✓ Stored but ignored by filters
    "user:alice",         # ✓ Stored but ignored (unrecognized namespace)
    "workflow:special"    # ✓ Stored but ignored (unrecognized namespace)
]
```

This design allows flexibility for users to add their own organizational tags while maintaining a well-defined set of tags that the installation system understands.

## Tag Taxonomy

### Platform Tags

#### Operating System (`os:`)
- `os:macos` - macOS/Darwin systems
- `os:linux` - Linux distributions
- `os:windows` - Windows systems (future support)
- `os:bsd` - BSD variants (future support)

#### Architecture (`arch:`)
- `arch:x86_64` - 64-bit Intel/AMD processors
- `arch:arm64` - ARM 64-bit processors (Apple Silicon, ARM servers)
- `arch:x86` - 32-bit Intel/AMD processors
- `arch:arm` - 32-bit ARM processors

#### Distribution (`dist:`)
- `dist:ubuntu` - Ubuntu and derivatives
- `dist:debian` - Debian and derivatives
- `dist:fedora` - Fedora, RHEL, CentOS Stream
- `dist:arch` - Arch Linux and derivatives
- `dist:centos` - CentOS Legacy
- `dist:rhel` - Red Hat Enterprise Linux
- `dist:opensuse` - openSUSE distributions
- `dist:alpine` - Alpine Linux

#### Distribution Type (`disttype:`)
- `disttype:atomic` - Atomic/immutable distributions (rpm-ostree, ostree-based)
- `disttype:traditional` - Traditional mutable distributions
- `disttype:container` - Container-based distributions

#### Desktop Environment (`de:`)
- `de:gnome` - GNOME desktop environment
- `de:kde` - KDE Plasma desktop
- `de:xfce` - XFCE desktop environment
- `de:hyprland` - Hyprland wayland compositor
- `de:sway` - Sway wayland compositor
- `de:i3` - i3 window manager
- `de:qtile` - Qtile window manager
- `de:awesome` - Awesome window manager
- `de:dwm` - Dynamic window manager
- `de:bspwm` - Binary space partitioning window manager
- `de:openbox` - Openbox window manager
- `de:lxde` - LXDE desktop environment
- `de:mate` - MATE desktop environment
- `de:cinnamon` - Cinnamon desktop environment
- `de:budgie` - Budgie desktop environment
- `de:pantheon` - Pantheon desktop (elementary OS)
- `de:niri` - Niri wayland compositor

#### Package Manager (`pm:`)
- `pm:homebrew` - Homebrew packages (any platform where Homebrew is available)
- `pm:homebrew:darwin` - Homebrew packages specifically for macOS
- `pm:homebrew:linux` - Homebrew packages specifically for Linux
- `pm:homebrew:cask` - Homebrew casks (macOS GUI applications)
- `pm:apt` - APT packages (Debian/Ubuntu)
- `pm:pacman` - Pacman packages (Arch)
- `pm:dnf` - DNF packages (Fedora/RHEL)
- `pm:flatpak` - Flatpak applications
- `pm:snap` - Snap packages
- `pm:custom` - Custom installation commands

**Note on Homebrew tags**: 
- Use `pm:homebrew` when a package works with Homebrew on both macOS and Linux
- Use `pm:homebrew:darwin` or `pm:homebrew:linux` when a package only works on a specific platform
- Use `pm:homebrew:cask` for Homebrew casks (macOS GUI applications) - these are automatically Darwin-only
- The platform-specific tags are more specific and will override the general `pm:homebrew` tag during filtering
- Cask packages should typically also include `os:macos` as they are macOS-specific GUI applications

### Software Category Tags (`cat:`)

#### Development Tools
- `cat:development` - General development tools
- `cat:editor` - Text/code editors
- `cat:ide` - Integrated development environments
- `cat:vcs` - Version control systems
- `cat:compiler` - Compilers and build tools
- `cat:debugger` - Debugging tools
- `cat:database-tools` - Database management tools
- `cat:api-tools` - API development and testing tools

#### System Tools
- `cat:system` - System administration tools
- `cat:monitoring` - System monitoring and metrics
- `cat:security` - Security and cryptography tools
- `cat:backup` - Backup and archival tools
- `cat:virtualization` - Virtualization and containers
- `cat:filesystem` - Filesystem and storage tools
- `cat:network-tools` - Network utilities and diagnostics

#### Network and Communication
- `cat:network` - General networking tools
- `cat:browser` - Web browsers
- `cat:communication` - Chat and messaging clients
- `cat:email` - Email clients and tools
- `cat:file-transfer` - File transfer and sync tools
- `cat:remote-access` - Remote access and VPN tools

#### Multimedia and Graphics
- `cat:audio` - Audio players, editors, and tools
- `cat:video` - Video players, editors, and tools
- `cat:graphics` - Image editing and graphics tools
- `cat:photography` - Photography and image management
- `cat:3d-graphics` - 3D modeling and rendering
- `cat:streaming` - Media streaming tools

#### Productivity and Office
- `cat:productivity` - General productivity tools
- `cat:office` - Office suites and document tools
- `cat:text-processing` - Document creation and editing
- `cat:presentation` - Presentation software
- `cat:spreadsheet` - Spreadsheet applications
- `cat:note-taking` - Note-taking and knowledge management
- `cat:pdf` - PDF viewers and editors
- `cat:calendar` - Calendar and scheduling tools

#### Command Line and Terminal
- `cat:cli-tool` - Command-line utilities
- `cat:shell` - Shells and shell tools
- `cat:terminal` - Terminal emulators and multiplexers
- `cat:text-manipulation` - Text processing tools (sed, awk, etc.)

#### Gaming and Entertainment
- `cat:gaming` - Games and gaming platforms
- `cat:emulation` - Emulators and compatibility layers
- `cat:entertainment` - Entertainment applications

#### Creative and Design
- `cat:design` - Design and creative tools
- `cat:publishing` - Desktop publishing
- `cat:music-production` - Music creation and production
- `cat:video-production` - Video editing and production

### Machine Role Tags (`role:`)

#### Environment Types
- `role:desktop` - Full GUI desktop environment
- `role:server` - Production server environment
- `role:headless` - No GUI, command-line only
- `role:container` - Container/microservice environment
- `role:embedded` - Embedded or IoT systems

#### Use Case Roles
- `role:development` - Software development workstation
- `role:gaming` - Gaming-focused setup
- `role:media-center` - Entertainment and media consumption
- `role:content-creation` - Content creation and editing
- `role:data-science` - Data analysis and machine learning
- `role:devops` - DevOps and infrastructure management
- `role:design` - Graphic design and creative work
- `role:minimal` - Lightweight/minimal installation

#### Specialized Environments
- `role:ci-cd` - Continuous integration/deployment
- `role:testing` - Testing and QA environments
- `role:demo` - Demonstration or presentation systems
- `role:educational` - Educational or training environments

### Installation Priority Tags

#### Priority Levels (`priority:`)
- `priority:essential` - Must-have tools for basic functionality
- `priority:recommended` - Commonly used, highly recommended tools
- `priority:optional` - Nice-to-have tools for specific workflows
- `priority:experimental` - Cutting-edge or unstable tools

#### Installation Scope (`scope:`)
- `scope:core` - Minimal essential installation
- `scope:extended` - Full-featured installation
- `scope:workflow-specific` - Tools for specific workflows only
- `scope:power-user` - Advanced tools for power users

## TOML Schema

### Package Entry Structure

```toml
[package-name]
# Existing fields (maintained for backward compatibility)
arch-pkg = "package-name"
apt-pkg = "package-name"
# Note: brew-supports-darwin and brew-supports-linux will be replaced by tags

# New tagging system
tags = [
    # Platform support
    "os:linux", "os:macos",
    "arch:x86_64", "arch:arm64",
    "dist:ubuntu", "dist:arch",
    "pm:apt", "pm:pacman", "pm:homebrew:darwin",
    
    # Software categorization
    "cat:development", "cat:vcs",
    
    # Target roles
    "role:desktop", "role:development",
    
    # Installation priority
    "priority:recommended",
    "scope:extended"
]

# Enhanced metadata (optional)
description = "Git version control system"
categories = ["Development", "Version Control"]  # Human-readable categories
keywords = ["git", "version-control", "scm"]     # Search keywords
```

### Tag Migration Examples

#### Before (Current System)
```toml
[git]
arch-pkg = "git"
apt-pkg = "git"
brew-supports-darwin = true
brew-supports-linux = true
description = "Distributed version control system"
```

#### After (Tagged System)
```toml
[git]
# Legacy fields will be removed after migration
arch-pkg = "git"
apt-pkg = "git"

# New tag-based system
tags = [
    "os:linux", "os:macos",
    "pm:apt", "pm:pacman", "pm:homebrew:darwin", "pm:homebrew:linux",
    "cat:development", "cat:vcs",
    "role:development", "role:desktop",
    "priority:essential"
]
description = "Distributed version control system"
```

## Query System

### Tag Query Language

#### Basic Queries
- Single tag: `os:macos`
- Multiple tags (AND): `os:macos AND cat:development`
- Multiple tags (OR): `role:desktop OR role:development`
- Negation: `NOT os:windows`

#### Complex Queries
```
# Development tools for macOS desktop
os:macos AND role:desktop AND cat:development

# Essential tools but not GUI applications
priority:essential AND NOT cat:gui

# Linux tools excluding Arch-specific packages
os:linux AND NOT dist:arch

# Media tools for desktop or media center roles
(role:desktop OR role:media-center) AND cat:multimedia

# Packages safe for atomic/immutable distributions (no package layering)
disttype:atomic OR (pm:homebrew OR pm:flatpak OR pm:custom)

# Traditional distribution packages (allowing native package managers)
disttype:traditional AND (pm:apt OR pm:pacman OR pm:dnf)

# Bazzite gaming setup (atomic distro + gaming focus)
disttype:atomic AND (role:gaming OR cat:gaming)
```

### Special Considerations for Atomic Distributions

Atomic/immutable distributions like Bazzite, Silverblue, Kinoite, and openSUSE MicroOS have unique package management constraints:

- **Package Layering**: Native packages (rpm, deb) require `rpm-ostree` layering, which can cause issues and requires reboots
- **Container-Safe**: Homebrew, Flatpak, and custom installs work without system modification
- **Distrobox Integration**: Many tools can be run in containers without affecting the host system

The `disttype:atomic` tag helps identify packages that are optimized for these distributions, while `disttype:traditional` indicates packages that work better on conventional mutable distributions.

### API Functions

#### Tag Checking Functions
```python
# Check if package has specific tag
is_tag_set(package, "os:macos") -> bool

# Check if package has any of the specified tags
has_any_tags(package, ["cat:development", "cat:editor"]) -> bool

# Check if package has all specified tags
has_all_tags(package, ["os:linux", "role:desktop"]) -> bool

# Filter packages by tag query
filter_by_tags(packages, "os:macos AND cat:development") -> List[Package]

# Tag hierarchy matching
# pm:homebrew matches pm:homebrew, pm:homebrew:darwin, and pm:homebrew:linux
matches_tag_prefix(package, "pm:homebrew") -> bool
```

#### Platform Detection Integration
```python
# Current platform detection enhanced with tags
def get_current_platform_tags() -> List[str]:
    """Return tags matching the current platform"""
    return ["os:macos", "arch:arm64", "pm:homebrew"]

# Filter packages for current platform
def get_platform_packages(packages) -> List[Package]:
    """Get packages compatible with current platform"""
    platform_tags = get_current_platform_tags()
    return filter_packages_for_platform(packages, platform_tags)
```

## Use Cases and Examples

### Machine Role Filtering

#### Development Workstation
```bash
# Install essential development tools
just install-packages --query "role:development AND priority:essential"

# Install all development tools for desktop
just install-packages --query "role:development AND role:desktop"

# Install specific category of development tools
just install-packages --query "cat:editor OR cat:ide"
```

#### Headless Server
```bash
# Install only essential CLI tools
just install-packages --query "role:headless AND priority:essential"

# Install monitoring and system tools
just install-packages --query "role:server AND (cat:monitoring OR cat:system)"

# Exclude GUI applications
just install-packages --query "role:server AND NOT cat:gui"
```

#### Gaming Setup
```bash
# Install gaming and multimedia tools
just install-packages --query "role:gaming OR cat:gaming OR cat:multimedia"

# Install gaming tools for specific platform
just install-packages --query "os:macos AND role:gaming"
```

### Platform-Specific Installation

#### macOS Development Machine
```bash
# All development tools available on macOS
just install-packages --query "os:macos AND cat:development"

# Homebrew packages for macOS only
just install-packages --query "pm:homebrew:darwin"

# ARM64 optimized packages
just install-packages --query "arch:arm64"
```

#### Linux Desktop
```bash
# Desktop tools for Linux
just install-packages --query "os:linux AND role:desktop"

# Flatpak applications only
just install-packages --query "pm:flatpak"

# Ubuntu-specific packages
just install-packages --query "dist:ubuntu"
```

### Workflow-Specific Installation

#### Data Science Workflow
```bash
# Data science and development tools
just install-packages --query "role:data-science OR (cat:development AND scope:extended)"
```

#### Content Creation
```bash
# Creative tools and multimedia
just install-packages --query "role:content-creation OR cat:video-production OR cat:design"
```

#### DevOps Environment
```bash
# System administration and DevOps tools
just install-packages --query "role:devops OR cat:monitoring OR cat:virtualization"
```

## Migration Strategy

### Phase 1: Schema Extension
1. Add `tags` field to TOML schema
2. Implement TaggedPackageFilter class
3. Maintain backward compatibility with existing platform detection

### Phase 2: Gradual Migration
1. Auto-generate tags from existing platform flags
2. Add tags to high-priority packages manually
3. Update package generation to use tag-based filtering

### Phase 3: Enhanced Features
1. Auto-tagging based on package metadata
2. Machine profile configurations
3. Advanced query capabilities

### Phase 4: Full Migration
1. Migrate all packages to tagged system
2. Deprecate legacy platform flags
3. Simplify codebase by removing legacy code

## Implementation Details

### TaggedPackageFilter Class

```python
class TaggedPackageFilter:
    """Enhanced package filtering using tag-based queries"""
    
    def __init__(self, toml_data: Dict[str, Any], platform_detector: PlatformDetector):
        self.toml_data = toml_data
        self.platform = platform_detector
        self.platform_tags = self._get_platform_tags()
    
    def filter_by_query(self, query: str) -> Dict[str, Any]:
        """Filter packages using tag query language"""
        pass
    
    def get_packages_for_role(self, role: str) -> Dict[str, Any]:
        """Get packages appropriate for specific machine role"""
        pass
    
    def get_packages_by_category(self, category: str) -> Dict[str, Any]:
        """Get packages in specific category"""
        pass
```

### Migration Utilities

```python
def migrate_platform_flags_to_tags(package_entry: Dict[str, Any]) -> List[str]:
    """Convert existing platform flags to tags"""
    tags = []
    
    # Convert Homebrew platform support flags
    if package_entry.get('brew-supports-darwin'):
        tags.extend(['os:macos', 'pm:homebrew:darwin'])
    if package_entry.get('brew-supports-linux'):
        tags.extend(['os:linux', 'pm:homebrew:linux'])
    
    # Convert package manager availability
    if package_entry.get('arch-pkg'):
        tags.extend(['os:linux', 'dist:arch', 'pm:pacman'])
    if package_entry.get('apt-pkg'):
        tags.extend(['os:linux', 'dist:debian', 'dist:ubuntu', 'pm:apt'])
    if package_entry.get('fedora-pkg'):
        tags.extend(['os:linux', 'dist:fedora', 'pm:dnf'])
    
    return tags

def auto_categorize_package(package_name: str, description: str) -> List[str]:
    """Automatically suggest category tags based on package metadata"""
    pass
```

## Benefits

### For Users
- **Targeted Installation**: Install only what's needed for specific machine roles
- **Better Discovery**: Find packages by category and use case
- **Flexible Configuration**: Support complex installation scenarios
- **Future-Proof**: Easy adaptation to new platforms and use cases

### For Maintainers
- **Rich Metadata**: Better organization and understanding of package collection
- **Extensible System**: Easy addition of new categorization dimensions
- **Automated Workflows**: Support for automated package management
- **Clear Dependencies**: Better modeling of package relationships

### For the Ecosystem
- **Standardized Categorization**: Common vocabulary for package classification
- **Interoperability**: Tags can be shared with other package management tools
- **Community Contributions**: Clear structure for community package additions
- **Analytics**: Better insights into package usage patterns

## Future Enhancements

### Advanced Features
- **Dependency Relationships**: Model package dependencies using tags
- **Alternative Packages**: Support "package A OR package B" scenarios
- **Conditional Installation**: Install packages based on system state
- **Profile Management**: Pre-defined tag combinations for common setups

### Integration Opportunities
- **CI/CD Integration**: Use tags for automated testing environments
- **Container Optimization**: Tag-based minimal container package sets
- **Cloud Deployment**: Platform-specific cloud environment packages
- **Cross-Platform Development**: Unified package management across platforms

## Migration Timeline

### Immediate (Phase 1)
- [ ] Implement basic tagging schema
- [ ] Create TaggedPackageFilter class
- [ ] Add backward compatibility layer

### Short-term (Phase 2)
- [ ] Migrate high-priority packages to tagged system
- [ ] Update package generators to support tag filtering
- [ ] Create migration utilities

### Medium-term (Phase 3)
- [ ] Auto-tagging implementation
- [ ] Machine role configurations
- [ ] Enhanced query capabilities

### Long-term (Phase 4)
- [ ] Complete migration of all packages
- [ ] Remove legacy platform detection
- [ ] Advanced features and integrations