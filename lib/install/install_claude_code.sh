#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [ -n $sourced_install_claude_code ]; then
  return;
fi
sourced_install_claude_code=true

# TODO: make sure node and npm are installed and up to date,
# then use npm to install claude code
