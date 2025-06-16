#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if is_sourced; then
  if [ -n $sourced_install_homebrew_packages ]; then
    return;
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

if ! is_sourced; then
  install_homebrew_packages
  install_mac_only_homebrew_packages
fi
