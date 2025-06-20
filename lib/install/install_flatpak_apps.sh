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
	readarray -t flatpaks_list <"{{- .chezmoi.config.sourceDir -}}/Flatfile"
	flatpak install --user -y --noninteractive --or-update "${flatpaks_list[@]}"
}

if [ -z "$sourced_install_flatpak_apps" ]; then
    install_flatpak_apps
fi
