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
    # Ensure npm global bin directory is in PATH
    local npm_bin_dir="$HOME/.npm-global/bin"
    if [[ ":$PATH:" != *":$npm_bin_dir:"* ]]; then
        export PATH="$npm_bin_dir:$PATH"
        log_debug "Added npm global bin directory to PATH: $npm_bin_dir"
    fi

    # Check if Claude Code CLI is already installed
    if command -v claude >/dev/null 2>&1; then
        log_debug "Claude Code CLI already installed"
        return
    fi

    log_info "Installing Claude Code CLI via npm..."

    # Ensure npm is available
    if ! command -v npm >/dev/null 2>&1; then
        log_error "npm not available - please ensure Node.js is installed"
        return 1
    fi

    # Install Claude Code CLI via npm on all platforms
    if ! npm install -g @anthropic-ai/claude-code; then
        log_error "Failed to install Claude Code CLI via npm"
        return 1
    fi

    # Verify installation
    if command -v claude >/dev/null 2>&1; then
        log_info "Claude Code CLI installed successfully"
        log_info "Run 'claude --help' to get started"
        log_info "You may need to authenticate with 'claude auth login'"
    else
        log_warning "Claude Code CLI installation may have failed - please check manually"
        log_warning "You may need to add $npm_bin_dir to your PATH"
        return 1
    fi
}

if [ -z "$sourced_install_claude_code" ]; then
    install_claude_code_if_needed
fi
