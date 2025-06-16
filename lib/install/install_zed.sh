#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

if [ is_sourced && -n $sourced_install_zed ]; then
  return;
fi
sourced_install_zed=true

function install_zed() {
  if command -v zed; then
    return;
  fi

  if [ "$ID" == "darwin" ]; then
	brew install --cask zed
  else
	# Use the per-user installer by default on linux systems.
	curl -f https://zed.dev/install.sh | sh
  fi
}

if ! is_sourced; then
  install_zed
fi
