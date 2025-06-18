#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_homebrew_packages" ] && [ "$sourced_install_homebrew_packages" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_homebrew_packages=true
fi

# make sure we only source this once.

function install_homebrew_packages() {
	brew bundle install --upgrade --file="${DOTFILES}/Brewfile"
}

function install_mac_only_homebrew_packages() {
    brew bundle install --upgrade --file="${DOTFILES}/Brewfile-darwin"
}

if [ -z "$sourced_install_homebrew_packages" ]; then
    install_homebrew_packages
    install_mac_only_homebrew_packages
fi
