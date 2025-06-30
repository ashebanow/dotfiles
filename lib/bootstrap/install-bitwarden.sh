#!/usr/bin/env bash

# Bootstrap bitwarden installer
# Smart platform-aware bitwarden installation with fallbacks

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
    echo -e "${BLUE}[bootstrap-bitwarden]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[bootstrap-bitwarden]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[bootstrap-bitwarden]${NC} $*"
}

log_error() {
    echo -e "${RED}[bootstrap-bitwarden]${NC} $*" >&2
}

# Check if bitwarden CLI is available
check_bitwarden_cli() {
    command -v bw >/dev/null 2>&1
}

# Install bitwarden CLI via homebrew
install_bitwarden_homebrew() {
    log_info "Installing Bitwarden CLI via Homebrew..."
    
    # Ensure homebrew is available
    if ! command -v brew >/dev/null 2>&1; then
        log_info "Homebrew not found, installing first..."
        source "$SCRIPT_DIR/install-homebrew.sh"
        ensure_homebrew
    fi
    
    brew install bitwarden-cli
}

# Install bitwarden CLI on Arch Linux
install_bitwarden_arch() {
    log_info "Installing Bitwarden CLI on Arch Linux..."
    
    # Check if yay is available, install if needed
    if ! command -v yay >/dev/null 2>&1; then
        log_info "Installing yay AUR helper..."
        sudo pacman -S --needed --noconfirm git base-devel
        
        # Create temporary directory for yay installation
        local temp_dir
        temp_dir=$(mktemp -d)
        pushd "$temp_dir" >/dev/null
        
        git clone https://aur.archlinux.org/yay.git
        cd yay
        makepkg -si --noconfirm
        
        popd >/dev/null
        rm -rf "$temp_dir"
    fi
    
    # Install bitwarden-cli from AUR
    yay -S --needed --noconfirm bitwarden-cli
}

# Install bitwarden CLI on Debian-like systems
install_bitwarden_debian() {
    log_info "Installing Bitwarden CLI on Debian-like system..."
    
    # For Debian/Ubuntu, we'll use homebrew since there's no official package
    # and snap has permission issues with secret managers
    install_bitwarden_homebrew
}

# Install bitwarden CLI on Fedora-like systems
install_bitwarden_fedora() {
    log_info "Installing Bitwarden CLI on Fedora-like system..."
    
    # Check if available in official repos first
    if command -v dnf >/dev/null 2>&1; then
        if dnf list bitwarden-cli >/dev/null 2>&1; then
            sudo dnf install -y bitwarden-cli
            return 0
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum list bitwarden-cli >/dev/null 2>&1; then
            sudo yum install -y bitwarden-cli
            return 0
        fi
    fi
    
    # Fallback to homebrew
    log_warn "Bitwarden CLI not found in official repos, using Homebrew..."
    install_bitwarden_homebrew
}

# Install bitwarden CLI via direct download (fallback)
install_bitwarden_direct() {
    log_info "Installing Bitwarden CLI via direct download..."
    
    # Detect architecture
    local arch
    case "$(uname -m)" in
        "x86_64"|"amd64") arch="x64" ;;
        "aarch64"|"arm64") arch="arm64" ;;
        *) 
            log_error "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
    
    # Determine platform
    local platform
    if [[ "$BOOTSTRAP_IS_MACOS" == "true" ]]; then
        platform="macos"
    else
        platform="linux"
    fi
    
    # Download and install
    local download_url="https://github.com/bitwarden/clients/releases/latest/download/bw-${platform}-${arch}.zip"
    local temp_dir
    temp_dir=$(mktemp -d)
    local install_dir="$HOME/.local/bin"
    
    mkdir -p "$install_dir"
    
    log_info "Downloading from: $download_url"
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$temp_dir/bw.zip" "$download_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$temp_dir/bw.zip" "$download_url"
    else
        log_error "Neither curl nor wget available for download"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Extract and install
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$temp_dir/bw.zip" -d "$temp_dir"
        cp "$temp_dir/bw" "$install_dir/"
        chmod +x "$install_dir/bw"
    else
        log_error "unzip not available to extract Bitwarden CLI"
        rm -rf "$temp_dir"
        return 1
    fi
    
    rm -rf "$temp_dir"
    
    # Add to PATH for current session if not already there
    if [[ ":$PATH:" != *":$install_dir:"* ]]; then
        export PATH="$install_dir:$PATH"
    fi
    
    log_success "Bitwarden CLI installed to $install_dir/bw"
}

# Install bitwarden desktop app
install_bitwarden_desktop() {
    log_info "Installing Bitwarden desktop application..."
    
    if [[ "$BOOTSTRAP_IS_MACOS" == "true" ]]; then
        # macOS - use homebrew cask
        if command -v brew >/dev/null 2>&1; then
            brew install --cask bitwarden
        else
            log_warn "Homebrew not available, skipping desktop app installation"
            log_warn "Please install Bitwarden desktop manually from https://bitwarden.com/download/"
        fi
    elif [[ "$BOOTSTRAP_IS_ATOMIC" == "true" ]]; then
        # Atomic/immutable systems - use flatpak
        if command -v flatpak >/dev/null 2>&1; then
            flatpak install -y flathub com.bitwarden.desktop
        else
            log_warn "Flatpak not available on atomic system"
            log_warn "Please install Bitwarden desktop manually"
        fi
    else
        # Traditional Linux - try native package first, fallback to flatpak
        local installed=false
        
        if [[ "$BOOTSTRAP_IS_ARCH_LIKE" == "true" ]] && command -v yay >/dev/null 2>&1; then
            yay -S --needed --noconfirm bitwarden
            installed=true
        elif [[ "$BOOTSTRAP_IS_DEBIAN_LIKE" == "true" ]]; then
            # Check if snap is available and working
            if command -v snap >/dev/null 2>&1 && snap list >/dev/null 2>&1; then
                sudo snap install bitwarden
                installed=true
            fi
        elif [[ "$BOOTSTRAP_IS_FEDORA_LIKE" == "true" ]]; then
            # Check if available in repos
            if command -v dnf >/dev/null 2>&1 && dnf list bitwarden >/dev/null 2>&1; then
                sudo dnf install -y bitwarden
                installed=true
            fi
        fi
        
        # Fallback to flatpak if native installation failed
        if [[ "$installed" == "false" ]] && command -v flatpak >/dev/null 2>&1; then
            log_info "Using Flatpak as fallback..."
            flatpak install -y flathub com.bitwarden.desktop
        elif [[ "$installed" == "false" ]]; then
            log_warn "Could not install Bitwarden desktop automatically"
            log_warn "Please install manually from https://bitwarden.com/download/"
        fi
    fi
}

# Main installation function
ensure_bitwarden() {
    log_info "Ensuring Bitwarden CLI is installed..."
    
    # Check if already installed
    if check_bitwarden_cli; then
        log_info "Bitwarden CLI already installed: $(bw --version)"
        return 0
    fi
    
    # Choose installation method based on platform
    local success=false
    
    if [[ "$BOOTSTRAP_IS_MACOS" == "true" ]]; then
        # macOS - prefer homebrew
        if install_bitwarden_homebrew; then
            success=true
        fi
    elif [[ "$BOOTSTRAP_IS_ATOMIC" == "true" ]]; then
        # Atomic/immutable systems - use homebrew (only option)
        if install_bitwarden_homebrew; then
            success=true
        fi
    else
        # Traditional Linux - try native packages first
        if [[ "$BOOTSTRAP_IS_ARCH_LIKE" == "true" ]]; then
            if install_bitwarden_arch; then
                success=true
            fi
        elif [[ "$BOOTSTRAP_IS_DEBIAN_LIKE" == "true" ]]; then
            if install_bitwarden_debian; then
                success=true
            fi
        elif [[ "$BOOTSTRAP_IS_FEDORA_LIKE" == "true" ]]; then
            if install_bitwarden_fedora; then
                success=true
            fi
        fi
        
        # Fallback to homebrew if native installation failed
        if [[ "$success" == "false" ]] && [[ "$BOOTSTRAP_HAS_HOMEBREW" == "true" || -n "${HOMEBREW_PREFIX:-}" ]]; then
            log_warn "Native package installation failed, trying Homebrew..."
            if install_bitwarden_homebrew; then
                success=true
            fi
        fi
    fi
    
    # Final fallback - direct download
    if [[ "$success" == "false" ]]; then
        log_warn "Package manager installation failed, trying direct download..."
        if install_bitwarden_direct; then
            success=true
        fi
    fi
    
    # Verify installation
    if [[ "$success" == "true" ]] && check_bitwarden_cli; then
        log_success "Bitwarden CLI installed successfully: $(bw --version)"
    else
        log_error "Failed to install Bitwarden CLI"
        return 1
    fi
}

# Show bitwarden status
show_status() {
    echo "Bitwarden Status:"
    if check_bitwarden_cli; then
        echo "  CLI Installed: true"
        echo "  Version: $(bw --version)"
        echo "  Location: $(command -v bw)"
        
        # Check login status
        if bw login --check >/dev/null 2>&1; then
            echo "  Login Status: logged in"
        else
            echo "  Login Status: not logged in"
        fi
    else
        echo "  CLI Installed: false"
    fi
}

# Handle command line arguments
case "${1:-install}" in
    "install"|"ensure")
        ensure_bitwarden
        ;;
    "desktop")
        install_bitwarden_desktop
        ;;
    "cli")
        ensure_bitwarden
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Usage: $0 [install|ensure|desktop|cli|status]"
        echo "  install/ensure: Install Bitwarden CLI if needed (default)"
        echo "  desktop:        Install Bitwarden desktop application"
        echo "  cli:            Install only Bitwarden CLI"
        echo "  status:         Show Bitwarden installation status"
        exit 1
        ;;
esac