#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

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
	# TODO: this should prefer package managers if possible
	if [ command -v brew ]; then
		brew install chezmoi
		return 0
		# TODO: this should try other package managers too
	fi

	if [ ! "$(command -v chezmoi)" ]; then
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
