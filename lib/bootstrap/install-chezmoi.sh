#!/usr/bin/env bash

# Bootstrap chezmoi installer
# Cross-platform chezmoi installation wrapper

set -euo pipefail

# Get script directory for sourcing other bootstrap scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source platform detection if not already loaded
if [[ -z "${BOOTSTRAP_OS:-}" ]]; then
    source "$SCRIPT_DIR/detect-distro.sh"
    detect_platform
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[bootstrap-chezmoi]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[bootstrap-chezmoi]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[bootstrap-chezmoi]${NC} $*"
}

log_error() {
    echo -e "${RED}[bootstrap-chezmoi]${NC} $*" >&2
}

# Check if chezmoi is available
check_chezmoi() {
    command -v chezmoi >/dev/null 2>&1
}

# Install chezmoi via homebrew
install_chezmoi_homebrew() {
    log_info "Installing chezmoi via Homebrew..."
    
    # Ensure homebrew is available
    if ! command -v brew >/dev/null 2>&1; then
        log_info "Homebrew not found, installing first..."
        source "$SCRIPT_DIR/install-homebrew.sh"
        ensure_homebrew
    fi
    
    brew install chezmoi
}

# Install chezmoi via package manager
install_chezmoi_native() {
    log_info "Installing chezmoi via native package manager..."
    
    if [[ "$BOOTSTRAP_IS_ARCH_LIKE" == "true" ]]; then
        # Arch Linux - chezmoi is in community repo
        sudo pacman -S --needed --noconfirm chezmoi
    elif [[ "$BOOTSTRAP_IS_DEBIAN_LIKE" == "true" ]]; then
        # Debian/Ubuntu - try official repo first, fallback to direct install
        if apt list chezmoi 2>/dev/null | grep -q chezmoi; then
            sudo apt-get update
            sudo apt-get install -y chezmoi
        else
            log_warn "chezmoi not in official repos, falling back to direct install"
            return 1
        fi
    elif [[ "$BOOTSTRAP_IS_FEDORA_LIKE" == "true" ]]; then
        # Fedora/RHEL - chezmoi should be available
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y chezmoi
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y chezmoi
        else
            log_error "No supported package manager found"
            return 1
        fi
    else
        log_warn "Unsupported distribution for native installation"
        return 1
    fi
}

# Install chezmoi via direct download (official installer)
install_chezmoi_direct() {
    log_info "Installing chezmoi via official installer..."
    
    local install_dir="$HOME/.local/bin"
    mkdir -p "$install_dir"
    
    # Use the official chezmoi installer
    if command -v curl >/dev/null 2>&1; then
        sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$install_dir"
    elif command -v wget >/dev/null 2>&1; then
        sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$install_dir"
    else
        log_error "Neither curl nor wget available for download"
        return 1
    fi
    
    # Add to PATH for current session if not already there
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        export PATH="$install_dir:$PATH"
    fi
    
    log_success "chezmoi installed to $install_dir/chezmoi"
}

# Main installation function
ensure_chezmoi() {
    log_info "Ensuring chezmoi is installed..."
    
    # Check if already installed
    if check_chezmoi; then
        log_info "chezmoi already installed: $(chezmoi --version)"
        return 0
    fi
    
    # Choose installation method based on platform and availability
    local success=false
    
    if [[ "$BOOTSTRAP_IS_MACOS" == "true" ]]; then
        # macOS - prefer homebrew, fallback to direct
        if install_chezmoi_homebrew; then
            success=true
        elif install_chezmoi_direct; then
            success=true
        fi
    elif [[ "$BOOTSTRAP_IS_ATOMIC" == "true" ]]; then
        # Atomic/immutable systems - use homebrew or direct install
        if [[ "$BOOTSTRAP_HAS_HOMEBREW" == "true" ]] && install_chezmoi_homebrew; then
            success=true
        elif install_chezmoi_direct; then
            success=true
        fi
    else
        # Traditional Linux - try native first, then homebrew, then direct
        if install_chezmoi_native; then
            success=true
        elif [[ "$BOOTSTRAP_HAS_HOMEBREW" == "true" ]] && install_chezmoi_homebrew; then
            success=true
        elif install_chezmoi_direct; then
            success=true
        fi
    fi
    
    # Verify installation
    if [[ "$success" == "true" ]] && check_chezmoi; then
        log_success "chezmoi installed successfully: $(chezmoi --version)"
    else
        log_error "Failed to install chezmoi"
        return 1
    fi
}

# Initialize chezmoi with dotfiles repository
init_chezmoi() {
    local repo_url="${1:-}"
    local source_dir="${2:-}"
    
    if [[ -z "$repo_url" && -z "$source_dir" ]]; then
        log_error "Either repository URL or source directory must be provided"
        echo "Usage: $0 init <repo-url> [source-dir]"
        echo "   or: $0 init --source <source-dir>"
        return 1
    fi
    
    log_info "Initializing chezmoi..."
    
    if [[ -n "$source_dir" ]]; then
        # Initialize from local source directory
        log_info "Initializing from source directory: $source_dir"
        chezmoi init --source="$source_dir"
    else
        # Initialize from repository URL
        log_info "Initializing from repository: $repo_url"
        chezmoi init "$repo_url"
    fi
    
    log_success "chezmoi initialized successfully"
}

# Apply chezmoi configuration
apply_chezmoi() {
    log_info "Applying chezmoi configuration..."
    
    if ! check_chezmoi; then
        log_error "chezmoi not installed"
        return 1
    fi
    
    chezmoi apply
    log_success "chezmoi configuration applied"
}

# Show chezmoi status
show_status() {
    echo "Chezmoi Status:"
    if check_chezmoi; then
        echo "  Installed: true"
        echo "  Version: $(chezmoi --version)"
        echo "  Location: $(command -v chezmoi)"
        
        # Check if initialized
        if chezmoi source-path >/dev/null 2>&1; then
            echo "  Source Path: $(chezmoi source-path)"
            echo "  Initialized: true"
        else
            echo "  Initialized: false"
        fi
    else
        echo "  Installed: false"
    fi
}

# Handle command line arguments
case "${1:-install}" in
    "install"|"ensure")
        ensure_chezmoi
        ;;
    "init")
        shift
        if [[ "${1:-}" == "--source" ]]; then
            init_chezmoi "" "${2:-}"
        else
            init_chezmoi "${1:-}" "${2:-}"
        fi
        ;;
    "apply")
        apply_chezmoi
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Usage: $0 [install|ensure|init|apply|status]"
        echo "  install/ensure: Install chezmoi if needed (default)"
        echo "  init <repo>:    Initialize chezmoi with repository"
        echo "  init --source <dir>: Initialize chezmoi with source directory"
        echo "  apply:          Apply chezmoi configuration"
        echo "  status:         Show chezmoi installation status"
        exit 1
        ;;
esac