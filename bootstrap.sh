#!/usr/bin/env bash

# Bootstrap script for setting up dotfiles on a new machine
# This script handles the initial setup required before running install.sh

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_DIR="$SCRIPT_DIR/lib/bootstrap"
DEFAULT_REPO_URL="https://github.com/ashebanow/dotfiles.git"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[bootstrap]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[bootstrap]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[bootstrap]${NC} $*"
}

log_error() {
    echo -e "${RED}[bootstrap]${NC} $*" >&2
}

log_step() {
    echo -e "${CYAN}${BOLD}[bootstrap]${NC} $*"
}

# Show help
show_help() {
    cat << EOF
Bootstrap Script for Dotfiles Setup

USAGE:
    $0 [OPTIONS] [COMMAND]

DESCRIPTION:
    This script bootstraps a new machine with the minimum requirements needed
    to run the full dotfiles installation. It handles platform detection,
    installs Homebrew (where needed), Bitwarden CLI, and chezmoi.

COMMANDS:
    install         Complete bootstrap setup (default)
    detect          Show platform detection results
    homebrew        Install Homebrew only
    bitwarden       Install and setup Bitwarden only  
    chezmoi         Install chezmoi only
    status          Show installation status of all components

OPTIONS:
    --email EMAIL   Bitwarden email address (will prompt if not provided)
    --repo URL      Git repository URL for dotfiles (default: $DEFAULT_REPO_URL)
    --local-source  Use current directory as source instead of cloning
    --debug         Enable debug output
    --help          Show this help message

EXAMPLES:
    $0                                    # Full bootstrap
    $0 --email user@example.com           # Bootstrap with specific email
    $0 --repo https://github.com/user/dotfiles.git  # Custom repo
    $0 --local-source                     # Use current directory as source
    $0 detect                             # Show platform info
    $0 status                             # Show what's installed

WORKFLOW:
    1. Platform detection (OS, distribution, mutability)
    2. Install Homebrew (macOS, atomic Linux)
    3. Install Bitwarden CLI
    4. Setup Bitwarden authentication
    5. Install chezmoi
    6. Initialize chezmoi with dotfiles
    7. Ready to run install.sh

For more information, see: https://github.com/ashebanow/dotfiles
EOF
}

# Parse command line arguments
COMMAND="install"
BITWARDEN_EMAIL=""
REPO_URL="$DEFAULT_REPO_URL"
USE_LOCAL_SOURCE=false
DEBUG_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --email)
            if [[ -n "${2:-}" && "$2" != --* ]]; then
                BITWARDEN_EMAIL="$2"
                shift 2
            else
                log_error "--email requires an email address"
                exit 1
            fi
            ;;
        --repo)
            if [[ -n "${2:-}" && "$2" != --* ]]; then
                REPO_URL="$2"
                shift 2
            else
                log_error "--repo requires a repository URL"
                exit 1
            fi
            ;;
        --local-source)
            USE_LOCAL_SOURCE=true
            shift
            ;;
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        install|detect|homebrew|bitwarden|chezmoi|status)
            COMMAND="$1"
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Try '$0 --help' for more information." >&2
            exit 1
            ;;
    esac
done

# Set debug mode
if [[ "$DEBUG_MODE" == "true" ]]; then
    log_info "Debug mode enabled"
    set -x
fi

# Export email for sub-scripts
if [[ -n "$BITWARDEN_EMAIL" ]]; then
    export BITWARDEN_EMAIL="$BITWARDEN_EMAIL"
fi

# Source platform detection
source "$BOOTSTRAP_DIR/detect-distro.sh"

# Step 1: Platform Detection
step_detect_platform() {
    log_step "Step 1: Detecting platform..."
    detect_platform
    
    log_info "Platform Summary:"
    echo "  OS: $BOOTSTRAP_OS"
    if [[ "$BOOTSTRAP_IS_LINUX" == "true" ]]; then
        echo "  Distribution: $BOOTSTRAP_DISTRO"
        echo "  Atomic/Immutable: $BOOTSTRAP_IS_ATOMIC"
    fi
    echo "  Has Homebrew: $BOOTSTRAP_HAS_HOMEBREW"
    echo ""
}

# Step 2: Install Homebrew
step_install_homebrew() {
    log_step "Step 2: Installing Homebrew..."
    
    # Skip if not needed
    if [[ "$BOOTSTRAP_IS_LINUX" == "true" && "$BOOTSTRAP_IS_ATOMIC" != "true" ]]; then
        log_info "Traditional Linux detected - Homebrew installation optional"
        log_info "Skipping Homebrew installation (will be installed later if needed)"
        return 0
    fi
    
    source "$BOOTSTRAP_DIR/install-homebrew.sh"
    ensure_homebrew
    echo ""
}

# Step 3: Install Bitwarden
step_install_bitwarden() {
    log_step "Step 3: Installing Bitwarden CLI..."
    
    source "$BOOTSTRAP_DIR/install-bitwarden.sh"
    ensure_bitwarden
    echo ""
}

# Step 4: Setup Bitwarden Authentication
step_setup_bitwarden() {
    log_step "Step 4: Setting up Bitwarden authentication..."
    
    source "$BOOTSTRAP_DIR/setup-bitwarden.sh"
    setup_bitwarden_auth
    echo ""
}

# Step 5: Install chezmoi
step_install_chezmoi() {
    log_step "Step 5: Installing chezmoi..."
    
    source "$BOOTSTRAP_DIR/install-chezmoi.sh"
    ensure_chezmoi
    echo ""
}

# Step 6: Initialize chezmoi
step_initialize_chezmoi() {
    log_step "Step 6: Initializing chezmoi with dotfiles..."
    
    if [[ "$USE_LOCAL_SOURCE" == "true" ]]; then
        log_info "Using local source directory: $SCRIPT_DIR"
        chezmoi init --source="$SCRIPT_DIR"
    else
        log_info "Initializing from repository: $REPO_URL"
        chezmoi init "$REPO_URL"
    fi
    
    log_success "chezmoi initialized successfully"
    echo ""
}

# Full installation workflow
cmd_install() {
    log_info "Starting bootstrap installation..."
    echo ""
    
    step_detect_platform
    step_install_homebrew
    step_install_bitwarden
    step_setup_bitwarden
    step_install_chezmoi
    step_initialize_chezmoi
    
    log_success "Bootstrap complete!"
    echo ""
    log_info "Next steps:"
    echo "  1. Review the configuration in chezmoi source directory:"
    echo "     $(chezmoi source-path)"
    echo "  2. Run the full installation:"
    echo "     $(chezmoi source-path)/install.sh"
    echo ""
    log_info "For more information: $0 --help"
}

# Platform detection only
cmd_detect() {
    step_detect_platform
}

# Install homebrew only
cmd_homebrew() {
    step_detect_platform
    step_install_homebrew
}

# Install and setup bitwarden only
cmd_bitwarden() {
    step_detect_platform
    step_install_bitwarden
    step_setup_bitwarden
}

# Install chezmoi only
cmd_chezmoi() {
    step_detect_platform
    step_install_chezmoi
}

# Show status of all components
cmd_status() {
    step_detect_platform
    
    log_step "Installation Status:"
    
    # Homebrew status
    echo "Homebrew:"
    source "$BOOTSTRAP_DIR/install-homebrew.sh"
    show_status | sed 's/^/  /'
    echo ""
    
    # Bitwarden status
    echo "Bitwarden:"
    source "$BOOTSTRAP_DIR/install-bitwarden.sh"
    show_status | sed 's/^/  /'
    echo ""
    source "$BOOTSTRAP_DIR/setup-bitwarden.sh"
    show_status | sed 's/^/  /'
    echo ""
    
    # Chezmoi status
    echo "Chezmoi:"
    source "$BOOTSTRAP_DIR/install-chezmoi.sh"
    show_status | sed 's/^/  /'
    echo ""
}

# Execute the requested command
case "$COMMAND" in
    "install")
        cmd_install
        ;;
    "detect")
        cmd_detect
        ;;
    "homebrew")
        cmd_homebrew
        ;;
    "bitwarden")
        cmd_bitwarden
        ;;
    "chezmoi")
        cmd_chezmoi
        ;;
    "status")
        cmd_status
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        echo "Try '$0 --help' for more information." >&2
        exit 1
        ;;
esac