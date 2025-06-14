#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [ -n $sourced_install_homebrew ]; then
  return;
fi
sourced_install_homebrew=true

function install_homebrew_if_needed() {
  if command -v brew; then
      return 0
  fi
  # TODO: implement
}

function install_homebrew_packages() {
	brew bundle install --upgrade --file="${DOTFILES}/Brewfile"
}

function install_mac_only_homebrew_packages() {
    brew bundle install --upgrade --file="${DOTFILES}/Brewfile-darwin"
}
