#!/bin/bash
# Custom package installation script
# Processes packages that need custom installation commands

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common utilities
source "$SCRIPT_DIR/../common/all.sh"

# Function to check if a command is available
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check install condition
check_install_condition() {
    local condition="$1"
    if [[ -z "$condition" ]]; then
        return 0  # No condition means always install
    fi
    
    # Execute the condition command
    if eval "$condition" >/dev/null 2>&1; then
        return 0  # Condition met
    else
        return 1  # Condition not met
    fi
}

# Function to prompt for confirmation
prompt_confirmation() {
    local package_name="$1"
    local description="$2"
    
    echo ""
    log_info "Custom installation required for: $package_name"
    if [[ -n "$description" && "$description" != *"TODO:"* ]]; then
        echo "  Description: $description"
    fi
    
    if command_exists gum; then
        if gum confirm "Install $package_name with custom commands?"; then
            return 0
        else
            return 1
        fi
    else
        echo -n "Install $package_name with custom commands? [Y/n] "
        read -r response
        case "$response" in
            [nN]|[nN][oO])
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    fi
}

# Function to execute custom installation commands
execute_custom_install() {
    local package_name="$1"
    shift
    local commands=("$@")
    
    log_info "Installing $package_name with custom commands..."
    
    local command_count=0
    for cmd in "${commands[@]}"; do
        command_count=$((command_count + 1))
        log_info "  Step $command_count: $cmd"
        
        # Execute the command with proper error handling
        if eval "$cmd"; then
            log_info "    ✓ Step $command_count completed"
        else
            log_error "    ✗ Step $command_count failed: $cmd"
            return 1
        fi
    done
    
    log_info "✓ $package_name installed successfully"
    return 0
}

# Function to get platform-specific commands from JSON
get_platform_commands() {
    local json_data="$1"
    local package_name="$2"
    
    # Check platform-specific commands in order of specificity
    local commands=()
    local platform_key=""
    
    # Determine the most specific platform key
    if [[ "$is_arch_like" == "true" ]] && jq -e ".packages.\"$package_name\"[\"custom-install\"].is_arch_like" >/dev/null 2>&1 <<< "$json_data"; then
        platform_key="is_arch_like"
    elif [[ "$is_debian_like" == "true" ]] && jq -e ".packages.\"$package_name\"[\"custom-install\"].is_debian_like" >/dev/null 2>&1 <<< "$json_data"; then
        platform_key="is_debian_like"
    elif [[ "$is_fedora_like" == "true" ]] && jq -e ".packages.\"$package_name\"[\"custom-install\"].is_fedora_like" >/dev/null 2>&1 <<< "$json_data"; then
        platform_key="is_fedora_like"
    elif [[ "$is_darwin" == "true" ]] && jq -e ".packages.\"$package_name\"[\"custom-install\"].is_darwin" >/dev/null 2>&1 <<< "$json_data"; then
        platform_key="is_darwin"
    elif jq -e ".packages.\"$package_name\"[\"custom-install\"].is_linux" >/dev/null 2>&1 <<< "$json_data"; then
        # Check if we're on Linux and there's a generic Linux entry
        if [[ "$(uname -s)" == "Linux" ]]; then
            platform_key="is_linux"
        fi
    fi
    
    # Get commands for the platform or fall back to default
    if [[ -n "$platform_key" ]]; then
        while IFS= read -r cmd; do
            commands+=("$cmd")
        done < <(jq -r ".packages.\"$package_name\"[\"custom-install\"].\"$platform_key\"[]" <<< "$json_data")
    else
        # Fall back to default if no platform-specific commands
        while IFS= read -r cmd; do
            commands+=("$cmd")
        done < <(jq -r ".packages.\"$package_name\"[\"custom-install\"].default[]?" <<< "$json_data")
    fi
    
    printf '%s\n' "${commands[@]}"
}

# Function to process custom installation JSON file
process_custom_installations() {
    local custom_file="$1"
    
    if [[ ! -f "$custom_file" ]]; then
        log_info "No custom installation file found: $custom_file"
        return 0
    fi
    
    # Check if jq is available
    if ! command_exists jq; then
        log_error "jq is required to process custom_install.json but is not installed"
        return 1
    fi
    
    log_info "Processing custom installations from: $custom_file"
    echo ""
    
    # Read and validate JSON
    local json_data
    if ! json_data=$(jq '.' "$custom_file" 2>/dev/null); then
        log_error "Failed to parse JSON file: $custom_file"
        return 1
    fi
    
    local total_packages=0
    local installed_packages=0
    local skipped_packages=0
    local failed_packages=0
    
    # Get all package names
    local package_names=()
    while IFS= read -r name; do
        package_names+=("$name")
    done < <(jq -r '.packages | keys[]' <<< "$json_data")
    
    for package_name in "${package_names[@]}"; do
        total_packages=$((total_packages + 1))
        
        # Get package info
        local description=$(jq -r ".packages.\"$package_name\".description // \"\"" <<< "$json_data")
        local priority=$(jq -r ".packages.\"$package_name\"[\"custom-install-priority\"] // \"fallback\"" <<< "$json_data")
        local requires_confirmation=$(jq -r ".packages.\"$package_name\"[\"requires-confirmation\"] // false" <<< "$json_data")
        local install_condition=$(jq -r ".packages.\"$package_name\"[\"install-condition\"] // \"\"" <<< "$json_data")
        
        # Check install priority
        if [[ "$priority" == "never" ]]; then
            log_info "Skipping $package_name (priority: never)"
            skipped_packages=$((skipped_packages + 1))
            continue
        fi
        
        # Check install condition if specified
        if [[ -n "$install_condition" ]] && [[ "$install_condition" != "null" ]]; then
            if ! check_install_condition "$install_condition"; then
                log_info "Skipping $package_name (condition not met: $install_condition)"
                skipped_packages=$((skipped_packages + 1))
                continue
            fi
        fi
        
        # Check if package is already installed
        if [[ "$priority" == "fallback" ]] && command_exists "$package_name"; then
            log_info "Package already available: $package_name"
            skipped_packages=$((skipped_packages + 1))
            continue
        fi
        
        # Get platform-specific commands
        local commands=()
        while IFS= read -r cmd; do
            commands+=("$cmd")
        done < <(get_platform_commands "$json_data" "$package_name")
        
        if [[ ${#commands[@]} -eq 0 ]]; then
            log_warning "No commands found for package: $package_name on this platform"
            skipped_packages=$((skipped_packages + 1))
            continue
        fi
        
        # Interactive confirmation if required
        if [[ "$requires_confirmation" == "true" ]] && [[ -t 0 ]] && [[ -t 1 ]]; then
            if ! prompt_confirmation "$package_name" "$description"; then
                log_info "Skipped: $package_name"
                skipped_packages=$((skipped_packages + 1))
                continue
            fi
        fi
        
        # Execute the installation
        if execute_custom_install "$package_name" "${commands[@]}"; then
            installed_packages=$((installed_packages + 1))
        else
            log_error "Failed to install: $package_name"
            failed_packages=$((failed_packages + 1))
        fi
        
        echo ""
    done
    
    # Summary
    echo ""
    log_info "Custom installation summary:"
    echo "  Total packages: $total_packages"
    echo "  Installed: $installed_packages"
    echo "  Skipped: $skipped_packages"
    echo "  Failed: $failed_packages"
    
    if [[ $failed_packages -gt 0 ]]; then
        return 1
    else
        return 0
    fi
}

# Main function
main() {
    log_info "=== Custom Package Installation ==="
    
    # Determine the custom file location
    local custom_file="${1:-packages/custom_install.json}"
    
    # Make path absolute if relative
    if [[ "$custom_file" != /* ]]; then
        custom_file="$(pwd)/$custom_file"
    fi
    
    # Process custom installations
    if process_custom_installations "$custom_file"; then
        log_info "Custom installation completed successfully"
        return 0
    else
        log_error "Custom installation completed with errors"
        return 1
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi