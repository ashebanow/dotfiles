#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [ -n $sourced_install_github ]; then
  return;
fi
sourced_install_github=true

# TODO: install github CLI (gh), auth, and add the copilot extension.
# going to be tricky to do the auth without templating.
