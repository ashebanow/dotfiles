#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

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

function install_bitwarden_session_service_if_needed {
    # Only install if bitwarden is available
    if ! command -v bw >/dev/null 2>&1; then
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
        # Linux systemd user service
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
            log_debug "Bitwarden session service files not found"
        fi
    fi
}

function install_bitwarden_services() {
    install_bitwarden_session_service_if_needed
}

if [ -z "$sourced_install_bitwarden_services" ]; then
    install_bitwarden_services
fi