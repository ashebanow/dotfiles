#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"
source "${DOTFILES}/lib/install/package_mappings.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_homebrew_packages" ] && [ "$sourced_install_homebrew_packages" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_homebrew_packages=true
fi

# make sure we only source this once.

function install_homebrew_packages() {
    # First, install override packages (critical infrastructure)
    if [[ -f "${DOTFILES}/Brewfile-overrides" ]]; then
        log_info "Installing override packages (critical infrastructure)..."
        brew bundle install --file="${DOTFILES}/Brewfile-overrides"
        
        # Install Python dependencies needed for package analysis
        if command -v python3.11 >/dev/null 2>&1; then
            log_info "Installing Python dependencies for package management..."
            python3.11 -m pip install --user --quiet toml requests || {
                log_warn "Failed to install Python dependencies, package analysis may not work"
            }
        fi
    fi
    
    # Ensure virtual environment is available (required for proper dependencies)
    if [[ ! -f "${DOTFILES}/.venv/bin/python3" ]]; then
        log_error "Python virtual environment not found at ${DOTFILES}/.venv/bin/python3"
        log_error "Please run 'just setup-python' from ${DOTFILES} first"
        return 1
    fi
    PYTHON_CMD="${DOTFILES}/.venv/bin/python3"
    
    # Try to generate package lists from TOML first
    if [[ -f "${DOTFILES}/package_mappings.toml" ]] && [[ -f "${DOTFILES}/bin/package_generators.py" ]]; then
        log_info "Generating package lists from TOML using ${PYTHON_CMD}..."
        if "${PYTHON_CMD}" "${DOTFILES}/bin/package_generators.py" \
            --toml "${DOTFILES}/package_mappings.toml" \
            --original-brewfile "${DOTFILES}/Brewfile.in" \
            --output-dir "${DOTFILES}" > "${DOTFILES}/.package_generation.log" 2>&1; then
            log_info "✓ Generated package lists from TOML"
        else
            log_warn "Failed to generate from TOML, falling back to legacy processing"
            # Process Brewfile.in to create filtered Brewfile (legacy method)
            if ! process_brewfile; then
                log_error "Failed to process Brewfile.in"
                return 1
            fi
        fi
    else
        log_info "TOML system not available, using legacy processing"
        # Process Brewfile.in to create filtered Brewfile (legacy method)
        if ! process_brewfile; then
            log_error "Failed to process Brewfile.in"
            return 1
        fi
    fi
    
    # Install packages from the processed Brewfile
    if [[ -f "${DOTFILES}/Brewfile" ]]; then
        log_info "Installing platform-specific packages..."
        brew bundle install --upgrade --file="${DOTFILES}/Brewfile"
    else
        log_error "No Brewfile found for installation"
        return 1
    fi
}

function install_mac_only_homebrew_packages() {
    if ! $is_darwin; then
        return
    fi
    
    # The TOML generation above should have created Brewfile-darwin if needed
    if [[ -f "${DOTFILES}/Brewfile-darwin" ]]; then
        brew bundle install --upgrade --file="${DOTFILES}/Brewfile-darwin"
    else
        log_info "No Brewfile-darwin found, skipping macOS-specific packages"
    fi
}

if [ -z "$sourced_install_homebrew_packages" ]; then
    install_homebrew_packages
    install_mac_only_homebrew_packages
fi
