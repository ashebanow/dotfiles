#!/usr/bin/env bash

# Bootstrap bitwarden setup
# Handles Bitwarden authentication and session management for bootstrap

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
    echo -e "${BLUE}[bootstrap-bw-setup]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[bootstrap-bw-setup]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[bootstrap-bw-setup]${NC} $*"
}

log_error() {
    echo -e "${RED}[bootstrap-bw-setup]${NC} $*" >&2
}

# Configuration
BW_EMAIL="${BITWARDEN_EMAIL:-}"
SESSION_FILE="$HOME/.cache/bw-session"

# GUI password prompt
prompt_password() {
    local title="$1"
    local prompt="$2"
    
    if [[ "$BOOTSTRAP_IS_MACOS" == "true" ]]; then
        osascript -e "display dialog \"$prompt\" default answer \"\" with title \"$title\" with hidden answer" -e "text returned of result" 2>/dev/null || true
    else
        # Linux - try zenity, fallback to terminal
        if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
            zenity --password --title="$title" --text="$prompt" 2>/dev/null || true
        else
            # Terminal fallback
            echo -n "$prompt: " >&2
            read -rs password
            echo >&2
            echo "$password"
        fi
    fi
}

# Prompt for email if not set
prompt_email() {
    local email
    
    if [[ "$BOOTSTRAP_IS_MACOS" == "true" ]]; then
        email=$(osascript -e "display dialog \"Enter your Bitwarden email address:\" default answer \"\" with title \"Bitwarden Setup\"" -e "text returned of result" 2>/dev/null || true)
    else
        # Linux - try zenity, fallback to terminal
        if command -v zenity >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
            email=$(zenity --entry --title="Bitwarden Setup" --text="Enter your Bitwarden email address:" 2>/dev/null || true)
        else
            # Terminal fallback
            echo -n "Enter your Bitwarden email address: " >&2
            read -r email
        fi
    fi
    
    echo "$email"
}

# Check if bitwarden CLI is available
check_bitwarden_cli() {
    command -v bw >/dev/null 2>&1
}

# Check current session validity
is_session_valid() {
    local session="${1:-}"
    if [[ -z "$session" ]]; then
        return 1
    fi
    
    BW_SESSION="$session" bw status >/dev/null 2>&1
}

# Get current session from file
get_current_session() {
    if [[ -f "$SESSION_FILE" ]]; then
        cat "$SESSION_FILE"
    fi
}

# Save session to file
save_session() {
    local session="$1"
    mkdir -p "$(dirname "$SESSION_FILE")"
    echo "$session" > "$SESSION_FILE"
    chmod 600 "$SESSION_FILE"
}

# Clear session file
clear_session() {
    rm -f "$SESSION_FILE"
}

# Setup Bitwarden authentication
setup_bitwarden_auth() {
    log_info "Setting up Bitwarden authentication..."
    
    # Ensure bitwarden CLI is installed
    if ! check_bitwarden_cli; then
        log_info "Bitwarden CLI not found, installing..."
        source "$SCRIPT_DIR/install-bitwarden.sh"
        ensure_bitwarden
    fi
    
    # Check if current session is valid
    local current_session
    current_session=$(get_current_session)
    
    if is_session_valid "$current_session"; then
        log_info "Valid Bitwarden session already exists"
        export BW_SESSION="$current_session"
        return 0
    fi
    
    # Clear invalid session
    clear_session
    
    # Get email if not set
    if [[ -z "$BW_EMAIL" ]]; then
        log_info "Bitwarden email not set in environment"
        BW_EMAIL=$(prompt_email)
        if [[ -z "$BW_EMAIL" ]]; then
            log_error "No email provided"
            return 1
        fi
        
        # Export for current session
        export BITWARDEN_EMAIL="$BW_EMAIL"
        log_info "Using email: $BW_EMAIL"
    fi
    
    # Check if we need to login first
    if ! bw login --check &>/dev/null; then
        log_info "Not logged in to Bitwarden, attempting login..."
        
        local password
        password=$(prompt_password "Bitwarden Login" "Enter your Bitwarden master password for $BW_EMAIL")
        if [[ -z "$password" ]]; then
            log_error "No password provided"
            return 1
        fi
        
        # Attempt login
        local session
        session=$(echo "$password" | bw login "$BW_EMAIL" --raw 2>/dev/null) || {
            log_error "Login failed - please check your email and password"
            return 1
        }
        
        save_session "$session"
        export BW_SESSION="$session"
        log_success "Successfully logged in to Bitwarden"
    else
        # Already logged in, just need to unlock
        log_info "Already logged in, unlocking vault..."
        
        local password
        password=$(prompt_password "Bitwarden Unlock" "Enter your Bitwarden master password to unlock")
        if [[ -z "$password" ]]; then
            log_error "No password provided"
            return 1
        fi
        
        # Attempt unlock
        local session
        session=$(echo "$password" | bw unlock --raw 2>/dev/null) || {
            log_error "Unlock failed - please check your password"
            return 1
        }
        
        save_session "$session"
        export BW_SESSION="$session"
        log_success "Successfully unlocked Bitwarden vault"
    fi
}

# Test Bitwarden access
test_bitwarden_access() {
    log_info "Testing Bitwarden access..."
    
    if [[ -z "${BW_SESSION:-}" ]]; then
        local current_session
        current_session=$(get_current_session)
        if [[ -n "$current_session" ]]; then
            export BW_SESSION="$current_session"
        else
            log_error "No Bitwarden session available"
            return 1
        fi
    fi
    
    # Try to list items (just count them)
    local item_count
    item_count=$(BW_SESSION="$BW_SESSION" bw list items --length 2>/dev/null || echo "0")
    
    if [[ "$item_count" =~ ^[0-9]+$ ]]; then
        log_success "Bitwarden access confirmed - found $item_count items in vault"
        return 0
    else
        log_error "Failed to access Bitwarden vault"
        return 1
    fi
}

# Show current Bitwarden status
show_status() {
    echo "Bitwarden Setup Status:"
    
    if ! check_bitwarden_cli; then
        echo "  CLI Installed: false"
        return
    fi
    
    echo "  CLI Installed: true"
    echo "  Version: $(bw --version)"
    
    # Check login status
    if bw login --check >/dev/null 2>&1; then
        echo "  Login Status: logged in"
        
        # Check for email
        if [[ -n "${BITWARDEN_EMAIL:-}" ]]; then
            echo "  Email: $BITWARDEN_EMAIL"
        else
            echo "  Email: not set in environment"
        fi
        
        # Check session
        local current_session
        current_session=$(get_current_session)
        if is_session_valid "$current_session"; then
            echo "  Session: valid"
            
            # Test access
            if BW_SESSION="$current_session" bw list items --length >/dev/null 2>&1; then
                echo "  Vault Access: working"
            else
                echo "  Vault Access: failed"
            fi
        else
            echo "  Session: invalid or missing"
        fi
    else
        echo "  Login Status: not logged in"
    fi
}

# Handle command line arguments
case "${1:-setup}" in
    "setup"|"auth")
        setup_bitwarden_auth
        ;;
    "test")
        test_bitwarden_access
        ;;
    "clear")
        clear_session
        log_info "Bitwarden session cleared"
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Usage: $0 [setup|auth|test|clear|status]"
        echo "  setup/auth: Setup Bitwarden authentication (default)"
        echo "  test:       Test current Bitwarden access"
        echo "  clear:      Clear current session"
        echo "  status:     Show Bitwarden setup status"
        exit 1
        ;;
esac