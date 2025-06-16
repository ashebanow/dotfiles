#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if is_sourced; then
  if [ -n $sourced_install_claude_code ]; then
    return;
  fi
  sourced_install_claude_code=true
fi

# TODO: make sure node and npm are installed and up to date,
# then use npm to install claude code
function install_claude_code() {
}

if ! is_sourced; then
  install_claude_code
fi
