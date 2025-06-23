#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_claude_code" ] && [ "$sourced_install_claude_code" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_claude_code=true
fi

function install_claude_code_if_needed() {
    # Check if Claude CLI is already installed
    if pkg_installed "claude"; then
        log_debug "Claude Code CLI already installed"
        return
    fi

    log_info "Installing Claude Code CLI..."

    if $is_darwin; then
        # macOS: Install via Homebrew
        # First try to install the desktop app which includes the CLI
        if command -v brew >/dev/null 2>&1; then
            brew install --cask claude
            # Also install the standalone CLI if available
            brew install anthropics/claude/claude 2>/dev/null || {
                log_debug "Standalone Claude CLI not available via brew, desktop app CLI should be sufficient"
            }
        else
            log_error "Homebrew not available for Claude Code installation on macOS"
            return 1
        fi
    else
        # if command -v curl >/dev/null 2>&1; then
            # gum spin --title "Installing Claude Code CLI..." -- bash -c "curl -fsSL https://claude.ai/cli/install.sh | sh"
            gum spin --title "Installing Claude Code CLI..." -- bash -c "npm install -g @anthropic-ai/claude-code"
        # else
        #     log_error "Neither curl nor wget available for installing Claude Code CLI"
        #     return 1
        # fi
    fi

    # Verify installation
    if pkg_installed "claude"; then
        log_info "Claude Code CLI installed successfully"
        log_info "Run 'claude --help' to get started"
        log_info "You may need to authenticate with 'claude auth login'"
    else
        log_warning "Claude Code CLI installation may have failed - please check manually"
        return 1
    fi
}

if [ -z "$sourced_install_claude_code" ]; then
    install_claude_code_if_needed
fi
