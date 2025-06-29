#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_bitwarden_services" ] && [ "$sourced_install_bitwarden_services" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_bitwarden_services=true
fi

#--------------------------------------------------------------------
# INSTALL BITWARDEN SESSION SERVICE
#--------------------------------------------------------------------

function _bw_is_systemd_available {
    # Check if systemd is available and running for the user
    if command -v systemctl >/dev/null 2>&1; then
        # Check if user systemd is available
        systemctl --user status >/dev/null 2>&1
    else
        return 1
    fi
}

function _bw_install_shell_session_manager {
    log_info "Installing Bitwarden session management for shell environments..."
    
    # Create a simple session management script
    local session_script="$HOME/.local/bin/bw-session-manager"
    mkdir -p "$(dirname "$session_script")"
    
    cat > "$session_script" << 'EOF'
#!/usr/bin/env bash
# Bitwarden session manager for containers/non-systemd environments

BW_SESSION_FILE="$HOME/.cache/bw_session"
BW_SESSION_PID_FILE="$HOME/.cache/bw_session.pid"

# Ensure cache directory exists
mkdir -p "$HOME/.cache"

# Function to check if session is valid
is_session_valid() {
    if [[ -f "$BW_SESSION_FILE" ]]; then
        local session=$(cat "$BW_SESSION_FILE" 2>/dev/null)
        if [[ -n "$session" ]]; then
            BW_SESSION="$session" bw status --raw 2>/dev/null | grep -q '"status":"unlocked"'
        else
            return 1
        fi
    else
        return 1
    fi
}

# Function to refresh session
refresh_session() {
    if command -v bw >/dev/null 2>&1; then
        if ! is_session_valid; then
            echo "Bitwarden session expired or invalid. Please run 'bw login' and 'bw unlock' manually."
            rm -f "$BW_SESSION_FILE"
        fi
    fi
}

case "${1:-check}" in
    check)
        refresh_session
        ;;
    start)
        # Start background session checker
        if [[ ! -f "$BW_SESSION_PID_FILE" ]] || ! kill -0 "$(cat "$BW_SESSION_PID_FILE" 2>/dev/null)" 2>/dev/null; then
            (
                while true; do
                    refresh_session
                    sleep 3600  # Check every hour
                done
            ) &
            echo $! > "$BW_SESSION_PID_FILE"
            echo "Bitwarden session manager started in background"
        fi
        ;;
    stop)
        if [[ -f "$BW_SESSION_PID_FILE" ]]; then
            local pid=$(cat "$BW_SESSION_PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid"
            fi
            rm -f "$BW_SESSION_PID_FILE"
            echo "Bitwarden session manager stopped"
        fi
        ;;
esac
EOF
    
    chmod +x "$session_script"
    
    # Add session loading to shell configs
    local bw_session_snippet='
# Bitwarden session management
if [[ -f "$HOME/.cache/bw_session" ]]; then
    export BW_SESSION="$(cat "$HOME/.cache/bw_session" 2>/dev/null)"
fi

# Auto-check session on interactive shell startup
if [[ -n "$PS1" ]] && command -v bw-session-manager >/dev/null 2>&1; then
    bw-session-manager check >/dev/null 2>&1
fi
'
    
    # Add to .bashrc if it exists
    if [[ -f "$HOME/.bashrc" ]] && ! grep -q "bw-session-manager" "$HOME/.bashrc"; then
        echo "$bw_session_snippet" >> "$HOME/.bashrc"
        log_debug "Added Bitwarden session management to .bashrc"
    fi
    
    # Add to .zshrc if it exists
    if [[ -f "$HOME/.zshrc" ]] && ! grep -q "bw-session-manager" "$HOME/.zshrc"; then
        echo "$bw_session_snippet" >> "$HOME/.zshrc"
        log_debug "Added Bitwarden session management to .zshrc"
    fi
    
    # Add to fish config if it exists
    if [[ -f "$HOME/.config/fish/config.fish" ]] && ! grep -q "bw-session-manager" "$HOME/.config/fish/config.fish"; then
        cat >> "$HOME/.config/fish/config.fish" << 'EOF'

# Bitwarden session management
if test -f "$HOME/.cache/bw_session"
    set -gx BW_SESSION (cat "$HOME/.cache/bw_session" 2>/dev/null)
end

# Auto-check session on interactive shell startup
if status is-interactive; and type -q bw-session-manager
    bw-session-manager check >/dev/null 2>&1
end
EOF
        log_debug "Added Bitwarden session management to fish config"
    fi
    
    log_info "Bitwarden shell session manager installed. Run 'bw-session-manager start' to enable background checks."
}

function install_bitwarden_session_service_if_needed {
    # Only install if bitwarden is available
    declare -A bw_packages=(
        ["darwin"]="bitwarden-cli"
        ["arch"]="bitwarden-cli"
        ["fedora"]="bitwarden-cli"
    )
    if ! pkg_installed "bw" bw_packages; then
        log_debug "Bitwarden CLI not found, skipping session service setup"
        return
    fi

    if $is_darwin; then
        # macOS launchd service
        local plist_file="$HOME/Library/LaunchAgents/com.user.bitwarden-session.plist"
        if [[ -f "$plist_file" ]]; then
            log_info "Installing Bitwarden session service (macOS)..."
            launchctl unload "$plist_file" 2>/dev/null || true
            launchctl load "$plist_file" 2>/dev/null || {
                log_warn "Failed to load Bitwarden session service"
            }
        else
            log_debug "Bitwarden session plist not found at $plist_file"
        fi
    else
        # Linux: try systemd first, fall back to shell-based approach
        if _bw_is_systemd_available; then
            local service_file="$HOME/.config/systemd/user/bitwarden-session.service"
            local timer_file="$HOME/.config/systemd/user/bitwarden-session.timer"
            
            if [[ -f "$service_file" && -f "$timer_file" ]]; then
                log_info "Installing Bitwarden session service (systemd)..."
                systemctl --user daemon-reload 2>/dev/null || true
                systemctl --user enable bitwarden-session.timer 2>/dev/null || {
                    log_warn "Failed to enable Bitwarden session timer"
                }
                systemctl --user start bitwarden-session.timer 2>/dev/null || {
                    log_warn "Failed to start Bitwarden session timer"
                }
            else
                log_debug "Bitwarden session service files not found, falling back to shell manager"
                _bw_install_shell_session_manager
            fi
        else
            log_info "systemd not available (container environment?), using shell-based session management"
            _bw_install_shell_session_manager
        fi
    fi
}

function install_bitwarden_services() {
    install_bitwarden_session_service_if_needed
}

if [ -z "$sourced_install_bitwarden_services" ]; then
    install_bitwarden_services
fi