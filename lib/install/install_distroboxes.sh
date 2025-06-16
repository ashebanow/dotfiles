#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if is_sourced; then
  if [ -n $sourced_install_distroboxes ]; then
    return;
  fi
  sourced_install_distroboxes=true
fi

function install_distrobox_if_needed() {
	if command -v distrobox; then
		return 0
	fi

	# TODO: install distrobox
	return 0
}

function install_distroboxes() {
    # TODO: create our development distrobox(es)
    distrobox assemble create --file "${DOTFILES}/Distroboxfile"
}

if ! is_sourced; then
  install_distrobox_if_needed
  install_distroboxes
fi
