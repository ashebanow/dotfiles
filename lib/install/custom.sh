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
    info "Custom installation required for: $package_name"
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
    
    info "Installing $package_name with custom commands..."
    
    local command_count=0
    for cmd in "${commands[@]}"; do
        command_count=$((command_count + 1))
        info "  Step $command_count: $cmd"
        
        # Execute the command with proper error handling
        if eval "$cmd"; then
            success "    ✓ Step $command_count completed"
        else
            error "    ✗ Step $command_count failed: $cmd"
            return 1
        fi
    done
    
    success "✓ $package_name installed successfully"
    return 0
}

# Function to process custom installation file
process_custom_installations() {
    local custom_file="$1"
    
    if [[ ! -f "$custom_file" ]]; then
        info "No custom installation file found: $custom_file"
        return 0
    fi
    
    info "Processing custom installations from: $custom_file"
    echo ""
    
    local total_packages=0
    local installed_packages=0
    local skipped_packages=0
    local failed_packages=0
    
    # Read the file line by line
    while IFS='|' read -r package_name command1 command2 command3 command4 command5 command6 command7 command8 command9 command10; do
        # Skip comments and empty lines
        if [[ -z "$package_name" || "$package_name" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        total_packages=$((total_packages + 1))
        
        # Collect all non-empty commands
        local commands=()
        for cmd in "$command1" "$command2" "$command3" "$command4" "$command5" "$command6" "$command7" "$command8" "$command9" "$command10"; do
            if [[ -n "$cmd" ]]; then
                commands+=("$cmd")
            fi
        done
        
        if [[ ${#commands[@]} -eq 0 ]]; then
            warning "No commands found for package: $package_name"
            skipped_packages=$((skipped_packages + 1))
            continue
        fi
        
        # Check if package is already installed (basic check)
        if command_exists "$package_name"; then
            info "Package already available: $package_name"
            skipped_packages=$((skipped_packages + 1))
            continue
        fi
        
        # TODO: Parse metadata from TOML (requires-confirmation, install-condition, description)
        # For now, we'll implement basic confirmation prompting
        
        # Interactive confirmation for custom installs
        if [[ -t 0 ]] && [[ -t 1 ]]; then
            if ! prompt_confirmation "$package_name" ""; then
                info "Skipped: $package_name"
                skipped_packages=$((skipped_packages + 1))
                continue
            fi
        fi
        
        # Execute the installation
        if execute_custom_install "$package_name" "${commands[@]}"; then
            installed_packages=$((installed_packages + 1))
        else
            error "Failed to install: $package_name"
            failed_packages=$((failed_packages + 1))
        fi
        
        echo ""
    done < "$custom_file"
    
    # Summary
    echo ""
    info "Custom installation summary:"
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
    info "=== Custom Package Installation ==="
    
    # Determine the custom file location
    local custom_file="${1:-packages/Customfile}"
    
    # Make path absolute if relative
    if [[ "$custom_file" != /* ]]; then
        custom_file="$(pwd)/$custom_file"
    fi
    
    # Process custom installations
    if process_custom_installations "$custom_file"; then
        success "Custom installation completed successfully"
        return 0
    else
        error "Custom installation completed with errors"
        return 1
    fi
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi