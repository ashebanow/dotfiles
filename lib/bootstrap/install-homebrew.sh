#!/usr/bin/env bash

# Bootstrap homebrew installer
# Cross-platform homebrew installation for macOS and Linux

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
    echo -e "${BLUE}[bootstrap-homebrew]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[bootstrap-homebrew]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[bootstrap-homebrew]${NC} $*"
}

log_error() {
    echo -e "${RED}[bootstrap-homebrew]${NC} $*" >&2
}

# Check if homebrew is in PATH
check_homebrew_in_path() {
    command -v brew >/dev/null 2>&1
}

# Set up homebrew environment
setup_homebrew_environment() {
    local brew_prefix
    
    if [[ "$BOOTSTRAP_IS_MACOS" == "true" ]]; then
        # macOS homebrew paths
        if [[ -x "/opt/homebrew/bin/brew" ]]; then
            brew_prefix="/opt/homebrew"
        elif [[ -x "/usr/local/bin/brew" ]]; then
            brew_prefix="/usr/local"
        else
            log_error "Homebrew installed but cannot find brew binary"
            return 1
        fi
    else
        # Linux homebrew path
        brew_prefix="/home/linuxbrew/.linuxbrew"
        if [[ ! -x "$brew_prefix/bin/brew" ]]; then
            # Check user-local installation
            brew_prefix="$HOME/.linuxbrew"
            if [[ ! -x "$brew_prefix/bin/brew" ]]; then
                log_error "Homebrew installed but cannot find brew binary"
                return 1
            fi
        fi
    fi
    
    # Add to PATH for current session
    export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
    
    # Set up environment variables
    export HOMEBREW_PREFIX="$brew_prefix"
    export HOMEBREW_CELLAR="$brew_prefix/Cellar"
    export HOMEBREW_REPOSITORY="$brew_prefix/Homebrew"
    
    # Additional Linux-specific setup
    if [[ "$BOOTSTRAP_IS_LINUX" == "true" ]]; then
        export MANPATH="$brew_prefix/share/man:${MANPATH:-}"
        export INFOPATH="$brew_prefix/share/info:${INFOPATH:-}"
    fi
    
    log_info "Homebrew environment configured: $brew_prefix"
}

# Install homebrew
install_homebrew() {
    log_info "Installing Homebrew..."
    
    # Ensure curl is available
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required to install Homebrew"
        return 1
    fi
    
    # Download and run the official Homebrew install script
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Set up environment after installation
    setup_homebrew_environment
    
    # Verify installation
    if check_homebrew_in_path; then
        log_success "Homebrew installed successfully: $(brew --version | head -1)"
        return 0
    else
        log_error "Homebrew installation failed - brew command not found"
        return 1
    fi
}

# Install Linux dependencies for homebrew
install_linux_dependencies() {
    if [[ "$BOOTSTRAP_IS_LINUX" != "true" ]]; then
        return 0
    fi
    
    log_info "Installing Linux dependencies for Homebrew..."
    
    if [[ "$BOOTSTRAP_IS_ARCH_LIKE" == "true" ]]; then
        if command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --needed --noconfirm base-devel curl file git
        fi
    elif [[ "$BOOTSTRAP_IS_DEBIAN_LIKE" == "true" ]]; then
        if command -v apt >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y build-essential curl file git
        fi
    elif [[ "$BOOTSTRAP_IS_FEDORA_LIKE" == "true" ]]; then
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf groupinstall -y "Development Tools"
            sudo dnf install -y curl file git
        elif command -v yum >/dev/null 2>&1; then
            sudo yum groupinstall -y "Development Tools"
            sudo yum install -y curl file git
        fi
    else
        log_warn "Unknown Linux distribution - skipping dependency installation"
        log_warn "You may need to manually install: build tools, curl, file, git"
    fi
}

# Main installation function
ensure_homebrew() {
    # Skip if already available and in PATH
    if [[ "$BOOTSTRAP_HAS_HOMEBREW" == "true" ]] && check_homebrew_in_path; then
        log_info "Homebrew already available"
        setup_homebrew_environment
        return 0
    fi
    
    # If homebrew exists but not in PATH, try to set it up
    if [[ "$BOOTSTRAP_HAS_HOMEBREW" == "true" ]] && ! check_homebrew_in_path; then
        log_info "Homebrew installed but not in PATH, setting up environment..."
        setup_homebrew_environment
        if check_homebrew_in_path; then
            log_success "Homebrew environment configured successfully"
            return 0
        fi
    fi
    
    # Install Linux dependencies if needed
    if [[ "$BOOTSTRAP_IS_LINUX" == "true" ]] && [[ "$BOOTSTRAP_IS_ATOMIC" != "true" ]]; then
        install_linux_dependencies
    fi
    
    # Install homebrew
    install_homebrew
}

# Show homebrew status
show_status() {
    echo "Homebrew Status:"
    echo "  Available: $BOOTSTRAP_HAS_HOMEBREW"
    if command -v brew >/dev/null 2>&1; then
        echo "  Version: $(brew --version | head -1)"
        echo "  Prefix: $(brew --prefix)"
    else
        echo "  In PATH: false"
    fi
}

# Handle command line arguments
case "${1:-install}" in
    "install"|"ensure")
        ensure_homebrew
        ;;
    "status")
        show_status
        ;;
    "setup-env")
        setup_homebrew_environment
        ;;
    *)
        echo "Usage: $0 [install|ensure|status|setup-env]"
        echo "  install/ensure: Install homebrew if needed (default)"
        echo "  status:         Show homebrew status"
        echo "  setup-env:      Set up homebrew environment variables"
        exit 1
        ;;
esac