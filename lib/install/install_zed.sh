#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_zed" ] && [ "$sourced_install_zed" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_zed=true
fi

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

if [ -z "$sourced_install_zed" ]; then
    install_zed
fi
