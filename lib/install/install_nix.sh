#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [ -n $sourced_install_nix ]; then
  return;
fi
sourced_install_nix=true

function install_nix_if_needed() {
  # TODO: move the installer code here from install-prerequisites.
}

if is_sourced; then
  install_nix_if_needed
fi
