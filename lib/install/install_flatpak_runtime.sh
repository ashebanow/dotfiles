#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_flatpak_runtime" ] && [ "$sourced_install_flatpak_runtime" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_flatpak_runtime=true
fi

function install_flatpak_if_needed {
    if $is_darwin; then
        return
    fi

    if ! $need_flatpak; then
        # make sure that flathub content is available
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        return
    fi

    if is_arch_like; then
        sudo pacman -S flatpak
    elif is_debian_like; then
        sudo apt install flatpak
    elif is_fedora_like; then
        if command -v dnf5; then
            sudo dnf5 install flatpak
        else
            sudo dnf install flatpak
        fi
    else
        # give up for now
        log_error "Unsupported/unknown linux variant, cannot install flatpak"
        exit 1
    fi

    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    flatpak update --appstream
}

# Check prerequisites to set $need_flatpak
if ! pkg_installed "flatpak"; then
    need_flatpak=true
else
    need_flatpak=false
fi

if [ -z "$sourced_install_flatpak_runtime" ]; then
    install_flatpak_if_needed
fi