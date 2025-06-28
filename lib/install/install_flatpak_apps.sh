#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_flatpak_apps" ] && [ "$sourced_install_flatpak_apps" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_flatpak_apps=true
fi

function install_flatpak_apps {
	# Use DOTFILES environment variable instead of chezmoi template
	local flatfile="${DOTFILES}/packages/Flatfile"
	if [[ ! -f "$flatfile" ]]; then
		log_error "Flatfile not found at: $flatfile"
		return 1
	fi

	# Ensure flatpak is available before using it
	if ! command -v flatpak >/dev/null 2>&1; then
		log_error "flatpak not found, cannot install Flatpak apps"
		return 1
	fi

	readarray -t flatpaks_list <"$flatfile"
	flatpak install --user -y --noninteractive --or-update "${flatpaks_list[@]}"
}

if [ -z "$sourced_install_flatpak_apps" ]; then
    install_flatpak_apps
fi
