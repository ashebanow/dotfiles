# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

# make sure we only source this once.
if [ ! "${BASH_SOURCE[0]}" -ef "$0" ]; then
    if [ -n "$sourced_packages" ]; then
        return
    fi
    sourced_packages=true
fi

#######################################################################
# Package checking and management functions

# Check if a package/command is installed
# Usage: pkg_installed <command_name> [package_map_var_name]
# 
# Arguments:
#   command_name: The command to check for (e.g., "gh", "bw", "gum")
#   package_map_var_name: Optional name of associative array variable that maps
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
    local package_map_var="$2"
    
    # First check if the command exists
    if command -v "$command_name" >/dev/null 2>&1; then
        return 0
    fi
    
    # If no package mapping provided, just return the command check result
    if [[ -z "$package_map_var" ]]; then
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
    if [[ -n "$package_map_var" && -n "$platform_key" ]]; then
        # Use nameref to access the associative array
        local -n package_map_ref="$package_map_var"
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
    if [[ -n "$package_map_var" ]]; then
        if $is_darwin; then
            # Check if homebrew package is installed
            brew list "$package_name" >/dev/null 2>&1
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