#!/usr/bin/env bash

# Bootstrap platform detection script
# Detects OS, distribution, and system mutability for bootstrap decisions

set -euo pipefail

# Platform detection variables (exported for use by other scripts)
export BOOTSTRAP_OS=""
export BOOTSTRAP_DISTRO=""
export BOOTSTRAP_IS_MACOS=false
export BOOTSTRAP_IS_LINUX=false
export BOOTSTRAP_IS_ATOMIC=false
export BOOTSTRAP_IS_ARCH_LIKE=false
export BOOTSTRAP_IS_DEBIAN_LIKE=false
export BOOTSTRAP_IS_FEDORA_LIKE=false
export BOOTSTRAP_HAS_HOMEBREW=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[bootstrap]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[bootstrap]${NC} $*"
}

log_error() {
    echo -e "${RED}[bootstrap]${NC} $*" >&2
}

# Detect base OS
detect_base_os() {
    case "$(uname -s)" in
        "Darwin")
            BOOTSTRAP_OS="macos"
            BOOTSTRAP_IS_MACOS=true
            ;;
        "Linux")
            BOOTSTRAP_OS="linux"
            BOOTSTRAP_IS_LINUX=true
            ;;
        *)
            log_error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac
}

# Detect Linux distribution
detect_linux_distro() {
    if [[ ! "$BOOTSTRAP_IS_LINUX" == "true" ]]; then
        return
    fi

    # Check /etc/os-release first (most modern systems)
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release

        case "${ID:-}" in
            "arch"|"manjaro"|"endeavouros"|"garuda"|"cachyos")
                BOOTSTRAP_DISTRO="arch"
                BOOTSTRAP_IS_ARCH_LIKE=true
                ;;
            "ubuntu"|"debian"|"linuxmint"|"pop")
                BOOTSTRAP_DISTRO="debian"
                BOOTSTRAP_IS_DEBIAN_LIKE=true
                ;;
            "fedora"|"rhel"|"centos"|"rocky"|"almalinux")
                BOOTSTRAP_DISTRO="fedora"
                BOOTSTRAP_IS_FEDORA_LIKE=true
                ;;
            *)
                # Try to detect based on ID_LIKE
                case "${ID_LIKE:-}" in
                    *"arch"*)
                        BOOTSTRAP_DISTRO="arch"
                        BOOTSTRAP_IS_ARCH_LIKE=true
                        ;;
                    *"debian"*|*"ubuntu"*)
                        BOOTSTRAP_DISTRO="debian"
                        BOOTSTRAP_IS_DEBIAN_LIKE=true
                        ;;
                    *"fedora"*|*"rhel"*)
                        BOOTSTRAP_DISTRO="fedora"
                        BOOTSTRAP_IS_FEDORA_LIKE=true
                        ;;
                    *)
                        BOOTSTRAP_DISTRO="unknown"
                        log_warn "Unknown Linux distribution: ${ID:-unknown}"
                        ;;
                esac
                ;;
        esac
    else
        # Fallback detection methods
        if command -v pacman >/dev/null 2>&1; then
            BOOTSTRAP_DISTRO="arch"
            BOOTSTRAP_IS_ARCH_LIKE=true
        elif command -v apt >/dev/null 2>&1; then
            BOOTSTRAP_DISTRO="debian"
            BOOTSTRAP_IS_DEBIAN_LIKE=true
        elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
            BOOTSTRAP_DISTRO="fedora"
            BOOTSTRAP_IS_FEDORA_LIKE=true
        else
            BOOTSTRAP_DISTRO="unknown"
            log_warn "Could not detect Linux distribution"
        fi
    fi
}

# Detect if system is atomic/immutable
detect_atomic_system() {
    if [[ ! "$BOOTSTRAP_IS_LINUX" == "true" ]]; then
        return
    fi

    # Check for atomic/immutable indicators
    local atomic_indicators=(
        # Check os-release for atomic variants
        "$(grep -i "variant.*atomic" /etc/os-release 2>/dev/null || true)"
        "$(grep -i "variant_id.*atomic" /etc/os-release 2>/dev/null || true)"
        # Check for specific atomic distros
        "$(grep -i "silverblue\|kinoite\|bazzite\|bluefin" /etc/os-release 2>/dev/null || true)"
        # Check for ostree
        "$(test -d /ostree && echo "ostree" || true)"
        # Check for read-only root
        "$(findmnt / -o OPTIONS | grep -i "ro," 2>/dev/null || true)"
    )

    for indicator in "${atomic_indicators[@]}"; do
        if [[ -n "$indicator" ]]; then
            BOOTSTRAP_IS_ATOMIC=true
            log_info "Detected atomic/immutable system"
            return
        fi
    done

    # Additional checks for specific systems
    if [[ -f /usr/bin/rpm-ostree ]] || [[ -f /usr/bin/ostree ]]; then
        BOOTSTRAP_IS_ATOMIC=true
        log_info "Detected OSTree-based system"
        return
    fi
}

# Check if homebrew is already installed
detect_existing_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        BOOTSTRAP_HAS_HOMEBREW=true
        log_info "Homebrew already installed: $(brew --version | head -1)"
    fi
}

# Main detection function
detect_platform() {
    log_info "Detecting platform..."

    detect_base_os
    detect_linux_distro
    detect_atomic_system
    detect_existing_homebrew

    # Log detection results
    log_info "Platform detection results:"
    echo "  OS: $BOOTSTRAP_OS"
    if [[ "$BOOTSTRAP_IS_LINUX" == "true" ]]; then
        echo "  Distribution: $BOOTSTRAP_DISTRO"
        echo "  Atomic/Immutable: $BOOTSTRAP_IS_ATOMIC"
    fi
    echo "  Has Homebrew: $BOOTSTRAP_HAS_HOMEBREW"
}

# Export variables for sourcing
export_variables() {
    cat << EOF
export BOOTSTRAP_OS="$BOOTSTRAP_OS"
export BOOTSTRAP_DISTRO="$BOOTSTRAP_DISTRO"
export BOOTSTRAP_IS_MACOS=$BOOTSTRAP_IS_MACOS
export BOOTSTRAP_IS_LINUX=$BOOTSTRAP_IS_LINUX
export BOOTSTRAP_IS_ATOMIC=$BOOTSTRAP_IS_ATOMIC
export BOOTSTRAP_IS_ARCH_LIKE=$BOOTSTRAP_IS_ARCH_LIKE
export BOOTSTRAP_IS_DEBIAN_LIKE=$BOOTSTRAP_IS_DEBIAN_LIKE
export BOOTSTRAP_IS_FEDORA_LIKE=$BOOTSTRAP_IS_FEDORA_LIKE
export BOOTSTRAP_HAS_HOMEBREW=$BOOTSTRAP_HAS_HOMEBREW
EOF
}

# Run detection if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    detect_platform

    # Output variables for eval by calling script
    if [[ "${1:-}" == "--export" ]]; then
        export_variables
    fi
fi
