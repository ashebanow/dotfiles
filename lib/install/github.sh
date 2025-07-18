#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_github" ] && [ "$sourced_install_github" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_github=true
fi

function install_git_if_needed {
    if ! pkg_installed "git"; then
        log_info "Installing git..."
        pkg_install "git"
    fi
}

function install_github_cli_if_needed {
    # GitHub CLI has different package names on different platforms
    declare -A gh_packages=(
        ["arch"]="github-cli"
    )
    if ! pkg_installed "gh" gh_packages; then
        log_info "Installing GitHub CLI..."
        pkg_install "gh" gh_packages
    fi
}

function login_github_cli_if_needed {
    # Check if gh is already authenticated
    if gh auth status >/dev/null 2>&1; then
        log_debug "GitHub CLI is already authenticated"
        return 0
    fi

    log_info "GitHub CLI not authenticated, logging in..."

    # Check if bitwarden CLI is available
    declare -A bw_packages=(
        ["darwin"]="bitwarden-cli"
        ["arch"]="bitwarden-cli"
        ["fedora"]="bitwarden-cli"
    )
    if ! pkg_installed "bw" bw_packages; then
        log_info "Bitwarden CLI not found, installing prerequisites..."
        source "${DOTFILES}/lib/install/prerequisites.sh"
        install_prerequisites
    fi

    # Get GitHub token from Bitwarden
    local github_token
    github_token=$(bw get item "GitHub CLI Personal Access Token" --field token 2>/dev/null)

    if [ -z "$github_token" ]; then
        log_error "Failed to retrieve GitHub token from Bitwarden"
        log_error "Please ensure 'GitHub CLI Personal Access Token' exists in Bitwarden with 'token' field"
        return 1
    fi

    # Login using the token
    echo "$github_token" | gh auth login --with-token

    if [ $? -eq 0 ]; then
        log_info "Successfully authenticated with GitHub CLI"
    else
        log_error "Failed to authenticate with GitHub CLI"
        return 1
    fi
}

function install_github_cli_copilot_extensions {
    log_info "Installing GitHub CLI Copilot extensions..."
    if gh extension list | grep -q gh-copilot; then
        gh extension upgrade github/gh-copilot
    else
        gh extension install github/gh-copilot
    fi
}

if [ -z "$sourced_install_github" ]; then
    install_git_if_needed
    install_github_cli_if_needed
    login_github_cli_if_needed
    install_github_cli_copilot_extensions
fi
