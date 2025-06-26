#!/usr/bin/env bash

# Package name mappings between Homebrew and native package managers
# Data is stored in TOML format for better readability and maintainability

declare -A PACKAGE_DATA
MAPPINGS_FILE="${DOTFILES}/package_mappings.toml"

# Simple TOML parser for our specific format
load_package_mappings() {
    if [[ ! -f "$MAPPINGS_FILE" ]]; then
        log_error "Package mappings file not found: $MAPPINGS_FILE"
        return 1
    fi
    
    local current_package=""
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Parse section headers [package_name]
        if [[ "$line" =~ ^\[([^\]]+)\]$ ]]; then
            current_package="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Parse key-value pairs
        if [[ "$line" =~ ^([^=]+)[[:space:]]*=[[:space:]]*(.+)$ ]]; then
            local key="${BASH_REMATCH[1]// /}"  # Remove spaces
            local value="${BASH_REMATCH[2]}"
            
            # Remove quotes from value
            value="${value#\"}"
            value="${value%\"}"
            
            if [[ -n "$current_package" ]]; then
                PACKAGE_DATA["${current_package}.${key}"]="$value"
            fi
        fi
    done < "$MAPPINGS_FILE"
    
    log_debug "Loaded package mappings from $MAPPINGS_FILE"
}

# Get a package attribute value
get_package_attr() {
    local package="$1"
    local attr="$2"
    echo "${PACKAGE_DATA["${package}.${attr}"]:-}"
}

# Function to check if a homebrew package should be filtered out
# Returns 0 (true) if package should be filtered, 1 (false) if it should be kept
should_filter_package() {
    local brew_package="$1"
    
    # Extract package name from brew line (remove tap prefix if present)
    local package_name
    if [[ "$brew_package" == *"/"* ]]; then
        package_name="${brew_package##*/}"
    else
        package_name="$brew_package"
    fi
    
    # Remove quotes if present
    package_name="${package_name//\"/}"
    
    # Check if we have mapping data for this package
    local arch_pkg=$(get_package_attr "$package_name" "arch-pkg")
    local apt_pkg=$(get_package_attr "$package_name" "apt-pkg")
    local fedora_pkg=$(get_package_attr "$package_name" "fedora-pkg")
    local flatpak_pkg=$(get_package_attr "$package_name" "flatpak-pkg")
    
    # If no mapping exists, keep the package
    if [[ -z "$arch_pkg" && -z "$apt_pkg" && -z "$fedora_pkg" && -z "$flatpak_pkg" ]]; then
        return 1  # Keep the package
    fi
    
    # Check Arch-like platforms
    if [[ "$is_arch_like" == "true" ]] && [[ -n "$arch_pkg" ]] && grep -q "^${arch_pkg}$" "${DOTFILES}/Archfile" 2>/dev/null; then
        return 0  # Filter it out
    fi
    
    # Check Debian-like platforms
    if [[ "$is_debian_like" == "true" ]] && [[ -n "$apt_pkg" ]] && grep -q "^${apt_pkg}$" "${DOTFILES}/Aptfile" 2>/dev/null; then
        return 0  # Filter it out
    fi
    
    # Check Fedora-like platforms
    if [[ "$is_fedora_like" == "true" ]] && [[ -n "$fedora_pkg" ]] && [[ -f "${DOTFILES}/Fedorafile" ]] && grep -q "^${fedora_pkg}$" "${DOTFILES}/Fedorafile" 2>/dev/null; then
        return 0  # Filter it out
    fi
    
    # Check Flatpak on all Linux platforms
    if [[ "$is_darwin" != "true" ]] && [[ -n "$flatpak_pkg" ]] && grep -q "^${flatpak_pkg}$" "${DOTFILES}/Flatfile" 2>/dev/null; then
        return 0  # Filter it out
    fi
    
    return 1  # Keep the package
}

# Function to process Brewfile.in and create filtered Brewfile
process_brewfile() {
    local input_file="${DOTFILES}/Brewfile.in"
    local output_file="${DOTFILES}/Brewfile"
    
    if [[ ! -f "$input_file" ]]; then
        log_error "Brewfile.in not found at $input_file"
        return 1
    fi
    
    # Load package mappings from TOML file
    if ! load_package_mappings; then
        log_error "Failed to load package mappings"
        return 1
    fi
    
    local platform_desc="unknown"
    [[ "$is_darwin" == "true" ]] && platform_desc="Darwin"
    [[ "$is_arch_like" == "true" ]] && platform_desc="Arch-like"
    [[ "$is_debian_like" == "true" ]] && platform_desc="Debian-like"
    [[ "$is_fedora_like" == "true" ]] && platform_desc="Fedora-like"
    
    log_info "Processing Brewfile.in for platform: $platform_desc"
    
    # Create temporary file for processing
    local temp_file
    temp_file=$(mktemp)
    
    local filtered_count=0
    local total_count=0
    
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line" >> "$temp_file"
            continue
        fi
        
        # Handle tap lines
        if [[ "$line" =~ ^tap ]]; then
            echo "$line" >> "$temp_file"
            continue
        fi
        
        # Handle brew lines
        if [[ "$line" =~ ^brew ]]; then
            total_count=$((total_count + 1))
            
            # Extract package name from brew line
            local package_spec
            package_spec=$(echo "$line" | sed 's/^brew "\([^"]*\)".*/\1/')
            
            if should_filter_package "$package_spec"; then
                log_debug "Filtering out: $package_spec (available natively)"
                filtered_count=$((filtered_count + 1))
            else
                echo "$line" >> "$temp_file"
            fi
        else
            # Keep non-brew/tap lines as-is
            echo "$line" >> "$temp_file"
        fi
    done < "$input_file"
    
    # Move processed file to final location
    mv "$temp_file" "$output_file"
    
    log_info "Brewfile processed: $filtered_count/$total_count packages filtered out"
    
    return 0
}