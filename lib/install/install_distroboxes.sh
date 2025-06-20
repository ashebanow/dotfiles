#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_distroboxes" ] && [ "$sourced_install_distroboxes" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_distroboxes=true
fi

function install_distrobox_if_needed() {
	if pkg_installed "distrobox"; then
		return 0
	fi

	# TODO: install distrobox
	return 0
}

function install_distroboxes() {
    # TODO: create our development distrobox(es)
    distrobox assemble create --file "${DOTFILES}/Distroboxfile"
}

if [ -z "$sourced_install_distroboxes" ]; then
    install_distrobox_if_needed
    install_distroboxes
fi
