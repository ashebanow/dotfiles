# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

# make sure we only source this once.
if [ ! "${BASH_SOURCE[0]}" -ef "$0" ]; then
    if [ -n "${sourced_packages:-}" ]; then
        return
    fi
    sourced_packages=true
fi

#######################################################################
# Package checking and management functions

# Check if a package/command is installed
# Usage: pkg_installed <command_name> [package_map_name]
# 
# Arguments:
#   command_name: The command to check for (e.g., "gh", "bw", "gum")
#   package_map_name: Optional name of associative array variable that maps
#                         platform identifiers to package names
#
# The package_map should use these platform keys:
#   - "darwin" for macOS (homebrew)
#   - "arch" for Arch-like systems
#   - "debian" for Debian-like systems  
#   - "fedora" for Fedora-like systems
#
# Note: You only need to specify mappings that differ from the command name.
#       The command name is used as fallback when no platform mapping exists.
#       When a package map is provided, package checking is prioritized over
#       command checking to ensure we get the correct package.
#
# Examples:
#   pkg_installed "gum"  # Just check if 'gum' command exists
#   
#   declare -A gh_packages=(["arch"]="github-cli")  # Only specify differences
#   pkg_installed "gh" gh_packages  # Uses "gh" for other platforms
#
# Returns 0 if installed, 1 if not installed
function pkg_installed() {
    local command_name="$1"
    local package_map="$2"
    
    # First check if the command exists
    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi
    
    # If no package mapping provided, just return the command check result
    if [[ -z "$package_map" ]]; then
        return 1
    fi
    
    # Get the package name for current platform from the mapping
    local package_name=""
    local platform_key=""
    
    # Determine platform key for package mapping
    if $is_darwin; then
        platform_key="darwin"
    elif $is_arch_like; then
        platform_key="arch"
    elif $is_debian_like; then
        platform_key="debian"
    elif $is_fedora_like; then
        platform_key="fedora"
    fi
    
    # Get package name for current platform from mapping (if provided)
    if [[ -n "$package_map" && -n "$platform_key" ]]; then
        # Use nameref to access the associative array
        local -n package_map_ref="$package_map"
        package_name="${package_map_ref[$platform_key]:-}"
        
        # Fall back to command name if platform-specific mapping not found
        if [[ -z "$package_name" ]]; then
            package_name="$command_name"
        fi
    else
        # No mapping provided or unknown platform, use command name
        package_name="$command_name"
    fi
    
    # Check if package is installed using platform-specific methods
    # (We prioritize package checking over command checking when mapping is provided)
    if [[ -n "$package_map" ]]; then
        if $is_darwin; then
            # Check if homebrew package is installed (only if brew exists)
            if command -v brew >/dev/null 2>&1; then
                brew list "$package_name" >/dev/null 2>&1
            else
                return 1  # brew not available, package not installed
            fi
        elif $is_arch_like; then
            # Check if pacman package is installed
            pacman -Qi "$package_name" >/dev/null 2>&1
        elif $is_debian_like; then
            # Check if apt package is installed
            dpkg -l "$package_name" >/dev/null 2>&1
        elif $is_fedora_like; then
            # Check if dnf/rpm package is installed
            if command -v dnf >/dev/null 2>&1; then
                dnf list installed "$package_name" >/dev/null 2>&1
            else
                rpm -q "$package_name" >/dev/null 2>&1
            fi
        else
            # Unknown platform, fall back to command check
            return 1
        fi
    else
        # No package name mapping available
        return 1
    fi
}

# Install a package using the appropriate package manager
# Usage: pkg_install <command_name> [package_map] [repo_map] [pre_install_map] [post_install_map] [custom_install_map]
# 
# Arguments:
#   command_name: The command/package to install (e.g., "gh", "bw", "gum")
#   package_map: Optional name of associative array variable that maps
#                platform identifiers to package names
#   repo_map: Optional name of associative array variable that maps
#             platform identifiers to repository URLs/tap names or JSON configs
#             - For "darwin": treated as tap name (e.g., "tailscale/tap")
#             - For "debian"/"ubuntu": can be URL or JSON with base_url, version_name, key_url
#             - For "fedora": treated as repository URL
#             - Ignored for "arch" (uses AUR or official repos)
#   pre_install_map: Optional name of associative array variable that maps
#                    platform identifiers to commands to run before installation
#   post_install_map: Optional name of associative array variable that maps
#                     platform identifiers to commands to run after installation
#   custom_install_map: Optional name of associative array variable that maps
#                       platform identifiers to custom installation commands
#                       (overrides normal package manager installation)
#
# Uses the same platform keys and mapping logic as pkg_installed.
# Leverages $package_manager variable when available.
#
# Examples:
#   pkg_install "gum"  # Install gum using default package manager
#   
#   declare -A gh_packages=(["arch"]="github-cli")
#   pkg_install "gh" gh_packages  # Install with platform-specific names
#
#   declare -A tailscale_repos=(["darwin"]="tailscale/tap" ["debian"]='${JSON_CONFIG}')
#   declare -A tailscale_pre=(["darwin"]="install_homebrew_if_needed")
#   declare -A tailscale_post=(["arch"]="sudo systemctl enable --now tailscaled")
#   pkg_install "tailscale" "" tailscale_repos tailscale_pre tailscale_post
#
# Returns 0 on success, 1 on failure
function pkg_install() {
    local command_name="$1"
    local package_map="$2"
    local repo_map="$3"
    local pre_install_map="$4"
    local post_install_map="$5"
    local custom_install_map="$6"
    
    # Get the package name for current platform (reuse logic from pkg_installed)
    local package_name=""
    local platform_key=""
    
    # Determine platform key for package mapping
    if $is_darwin; then
        platform_key="darwin"
    elif $is_arch_like; then
        platform_key="arch"
    elif $is_debian_like; then
        platform_key="debian"
    elif $is_fedora_like; then
        platform_key="fedora"
    fi
    
    # Get package name for current platform from mapping (if provided)
    if [[ -n "$package_map" && -n "$platform_key" ]]; then
        # Use nameref to access the associative array
        local -n package_map_ref="$package_map"
        package_name="${package_map_ref[$platform_key]:-}"
        
        # Fall back to command name if platform-specific mapping not found
        if [[ -z "$package_name" ]]; then
            package_name="$command_name"
        fi
    else
        # No mapping provided or unknown platform, use command name
        package_name="$command_name"
    fi
    
    # Run pre-install hooks
    _pkg_run_pre_hooks "$pre_install_map" "$platform_key"
    
    # Check for custom installation method
    if _pkg_has_custom_install "$custom_install_map" "$platform_key"; then
        _pkg_run_custom_install "$custom_install_map" "$platform_key"
    else
        # Normal package installation flow
        _pkg_add_repository "$repo_map" "$platform_key"
        _pkg_install_package "$package_name"
    fi
    
    # Run post-install hooks
    _pkg_run_post_hooks "$post_install_map" "$platform_key"
}

# Helper function to run pre-install hooks
_pkg_run_pre_hooks() {
    local pre_install_map="$1"
    local platform_key="$2"
    
    if [[ -n "$pre_install_map" && -n "$platform_key" ]]; then
        local -n pre_install_ref="$pre_install_map"
        local pre_command="${pre_install_ref[$platform_key]:-}"
        if [[ -n "$pre_command" ]]; then
            eval "$pre_command" || return 1
        fi
    fi
}

# Helper function to check if custom installation is specified
_pkg_has_custom_install() {
    local custom_install_map="$1"
    local platform_key="$2"
    
    if [[ -n "$custom_install_map" && -n "$platform_key" ]]; then
        local -n custom_install_ref="$custom_install_map"
        local custom_command="${custom_install_ref[$platform_key]:-}"
        [[ -n "$custom_command" ]]
    else
        return 1
    fi
}

# Helper function to run custom installation
_pkg_run_custom_install() {
    local custom_install_map="$1"
    local platform_key="$2"
    
    local -n custom_install_ref="$custom_install_map"
    local custom_command="${custom_install_ref[$platform_key]:-}"
    if [[ -n "$custom_command" ]]; then
        eval "$custom_command" || return 1
    fi
}

# Helper function to run post-install hooks
_pkg_run_post_hooks() {
    local post_install_map="$1"
    local platform_key="$2"
    
    if [[ -n "$post_install_map" && -n "$platform_key" ]]; then
        local -n post_install_ref="$post_install_map"
        local post_command="${post_install_ref[$platform_key]:-}"
        if [[ -n "$post_command" ]]; then
            eval "$post_command" || return 1
        fi
    fi
}

# Helper function to add repository
_pkg_add_repository() {
    local repo_map="$1"
    local platform_key="$2"
    
    if [[ -n "$repo_map" && -n "$platform_key" ]]; then
        local -n repo_map_ref="$repo_map"
        local repo_config="${repo_map_ref[$platform_key]:-}"
        
        if [[ -n "$repo_config" ]]; then
            if $is_darwin; then
                _pkg_add_repository_darwin "$repo_config"
            elif $is_debian_like; then
                _pkg_add_repository_debian "$repo_config"
            elif $is_fedora_like; then
                _pkg_add_repository_fedora "$repo_config"
            fi
        fi
    fi
}

# Darwin repository handling
_pkg_add_repository_darwin() {
    local repo_config="$1"
    
    if ! command -v brew >/dev/null 2>&1; then
        log_error "brew not found, cannot add repository: $repo_config"
        return 1
    fi
    
    # For homebrew, repo_config is treated as a tap name
    if ! brew tap | grep -q "^$repo_config$"; then
        brew tap "$repo_config"
    fi
}

# Debian/Ubuntu repository handling
_pkg_add_repository_debian() {
    local repo_config="$1"
    
    # Check if repo_config is valid JSON by testing with jq
    if echo "$repo_config" | jq empty >/dev/null 2>&1; then
        # Parse JSON config for Debian/Ubuntu repositories
        local base_url version_name key_url
        base_url=$(echo "$repo_config" | jq -r '.base_url // empty')
        version_name=$(echo "$repo_config" | jq -r '.version_name // empty')
        key_url=$(echo "$repo_config" | jq -r '.key_url // empty')
        
        # Auto-detect version if "auto" specified
        if [[ "$version_name" == "auto" ]]; then
            if command -v lsb_release >/dev/null 2>&1; then
                version_name=$(lsb_release -cs)
            elif [[ -f /etc/os-release ]]; then
                version_name=$(. /etc/os-release; echo "$VERSION_CODENAME")
            else
                # Fallback to generic names
                if $is_debian_like && grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
                    version_name="jammy"  # Ubuntu LTS fallback
                else
                    version_name="bookworm"  # Debian stable fallback
                fi
            fi
        fi
        
        # Add GPG key if specified
        if [[ -n "$key_url" ]]; then
            curl -fsSL "$key_url" | sudo gpg --dearmor -o "/usr/share/keyrings/$(basename "$key_url" .gpg).gpg"
            local keyring_path="/usr/share/keyrings/$(basename "$key_url" .gpg).gpg"
        fi
        
        # Add repository
        if [[ -n "$base_url" && -n "$version_name" ]]; then
            local repo_line="deb"
            if [[ -n "$keyring_path" ]]; then
                repo_line="$repo_line [signed-by=$keyring_path]"
            fi
            repo_line="$repo_line $base_url $version_name main"
            echo "$repo_line" | sudo tee "/etc/apt/sources.list.d/$(echo "$base_url" | sed 's|[^a-zA-Z0-9]|-|g').list" >/dev/null
        fi
        sudo apt-get update
    else
        # Simple repository URL handling (legacy)
        if [[ "$repo_config" == *".list" ]]; then
            # Direct .list file URL
            curl -fsSL "$repo_config" | sudo tee /etc/apt/sources.list.d/$(basename "$repo_config") >/dev/null
        else
            # Repository URL - add to sources
            echo "deb $repo_config" | sudo tee /etc/apt/sources.list.d/$(echo "$repo_config" | sed 's|[^a-zA-Z0-9]|-|g').list >/dev/null
        fi
        sudo apt-get update
    fi
}

# Fedora repository handling
_pkg_add_repository_fedora() {
    local repo_config="$1"
    
    # For dnf/fedora, add repository
    local pkg_mgr="${package_manager:-}"
    if [[ -z "$pkg_mgr" ]]; then
        if command -v dnf5 >/dev/null 2>&1; then
            pkg_mgr="dnf5"
        else
            pkg_mgr="dnf"
        fi
    fi
    
    if [[ "$pkg_mgr" == "dnf5" ]]; then
        sudo dnf5 config-manager --add-repo "$repo_config"
    else
        sudo dnf config-manager --add-repo "$repo_config"
    fi
}

# Helper function to ensure yay is available for AUR packages on Arch
_pkg_ensure_yay() {
    # Guard against recursion when installing yay itself
    if [[ "${_pkg_installing_yay:-}" == "true" ]]; then
        return 0
    fi
    
    if ! command -v yay >/dev/null 2>&1; then
        echo "Installing yay for AUR package support..."
        
        # Set recursion guard
        export _pkg_installing_yay="true"
        
        # Install prerequisites for yay
        sudo pacman -S --needed --noconfirm git base-devel
        
        # Install yay from AUR manually
        local temp_dir
        temp_dir=$(mktemp -d)
        pushd "$temp_dir" >/dev/null || return 1
        
        git clone https://aur.archlinux.org/yay.git
        cd yay || return 1
        makepkg -si --noconfirm
        
        popd >/dev/null || return 1
        rm -rf "$temp_dir"
        
        # Clear recursion guard
        unset _pkg_installing_yay
        
        if ! command -v yay >/dev/null 2>&1; then
            log_error "Failed to install yay"
            return 1
        fi
    fi
}

# Helper function to check if a package is available in official Arch repos
_pkg_is_arch_official() {
    local package_name="$1"
    
    # Try to find the package in official repos
    pacman -Si "$package_name" >/dev/null 2>&1
}

# Helper function to install package using appropriate package manager
_pkg_install_package() {
    local package_name="$1"
    
    if $is_darwin; then
        if ! command -v brew >/dev/null 2>&1; then
            log_error "brew not found, cannot install package: $package_name"
            return 1
        fi
        brew install "$package_name"
    elif $is_arch_like; then
        # Determine the best package manager for this package
        local pkg_mgr="${package_manager:-}"
        
        if [[ -z "$pkg_mgr" ]]; then
            # Auto-detect: try official repos first, then AUR
            if _pkg_is_arch_official "$package_name"; then
                pkg_mgr="pacman"
            else
                # Package not in official repos, need AUR helper
                _pkg_ensure_yay || return 1
                pkg_mgr="yay"
            fi
        elif [[ "$pkg_mgr" == "yay" ]]; then
            # Explicitly requested yay, ensure it's available
            _pkg_ensure_yay || return 1
        fi
        
        # Install with the determined package manager
        if [[ "$pkg_mgr" == "yay" ]]; then
            yay -S --needed --noconfirm "$package_name"
        else
            sudo pacman -S --needed --noconfirm "$package_name"
        fi
    elif $is_debian_like; then
        sudo apt-get update && sudo apt-get install -y "$package_name"
    elif $is_fedora_like; then
        # Use $package_manager if available, otherwise detect dnf/dnf5
        local pkg_mgr="${package_manager:-}"
        if [[ -z "$pkg_mgr" ]]; then
            if command -v dnf5 >/dev/null 2>&1; then
                pkg_mgr="dnf5"
            else
                pkg_mgr="dnf"
            fi
        fi
        sudo "$pkg_mgr" install -y "$package_name"
    else
        log_error "Unsupported platform for package installation"
        return 1
    fi
}