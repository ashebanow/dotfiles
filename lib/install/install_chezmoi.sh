#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_chezmoi" ] && [ "$sourced_install_chezmoi" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_chezmoi=true
fi

# variables
repo="git@github.com:ashebanow/dotfiles.git"
bin_dir="$HOME/.local/bin"

function install_chezmoi_if_needed {
	if pkg_installed "chezmoi"; then
		return
	fi

	# TODO: this should prefer package managers if possible
	log_info "Installing chezmoi..."
		if [ "$(command -v curl)" ]; then
			sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$bin_dir"
		elif [ "$(command -v wget)" ]; then
			sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$bin_dir"
		else
			echo "To install chezmoi, you must have curl or wget installed." >&2
			exit 1
		fi
	fi
}

if [ -z "$sourced_install_chezmoi" ]; then
    install_chezmoi_if_needed
fi
