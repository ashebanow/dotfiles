#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# source our library of install modules.
source "${DOTFILES}/lib/install/install_prerequisites.sh"
source "${DOTFILES}/lib/install/install_arch.sh"
source "${DOTFILES}/lib/install/install_bitwarden_services.sh"
source "${DOTFILES}/lib/install/install_chezmoi.sh"
source "${DOTFILES}/lib/install/install_distroboxes.sh"
source "${DOTFILES}/lib/install/install_flatpak_apps.sh"
source "${DOTFILES}/lib/install/install_homebrew_packages.sh"
source "${DOTFILES}/lib/install/install_github.sh"
source "${DOTFILES}/lib/install/install_nix.sh"

#######################################################################
# Phase 1: install universal packages and apps
show_spinner \
    "Installing required prerequisites..." \
    "${DOTFILES}/lib/install/install_prerequisites.sh" \
    "Installed required prerequisites."

# install arch packages here if appropriate.
# It is important that this be done early so that
# homebrew knows we already have commands installed.
# TODO: do the same for debian-like systems, and for
# mutable fedora distributions.
if $is_arch_like; then
    show_spinner \
        "Installing Arch packages..." \
        "${DOTFILES}/lib/install/install_arch.sh" \
        "Installed Arch packages."
fi

show_spinner \
    "Installing homebrew packages..." \
    "${DOTFILES}/lib/install/install_homebrew_packages.sh" \
    "Installed homebrew packages."

# show_spinner \
# 	"Installing nix..." \
# 	install_nix_if_needed \
# 	"Installed nix."

show_spinner \
    "Installing Flatpak runtime if needed..." \
    "${DOTFILES}/lib/install/install_flatpak_runtime.sh" \
    "Installed Flatpak runtime if needed."

show_spinner \
    "Installing Flatpak apps..." \
    "${DOTFILES}/lib/install/install_flatpak_apps.sh" \
    "Installed Flatpak apps."

show_spinner "Installing fonts..." \
    "${DOTFILES}/lib/install/install_fonts.sh" \
    "Installed fonts..."

show_spinner "Installing Claude Code..." \
    "${DOTFILES}/lib/install/install_claude_code.sh" \
    "Installed Claude Code."

show_spinner "Installing Zed..." \
    "${DOTFILES}/lib/install/install_zed.sh" \
    "Installed Zed."

show_spinner "Installing VSCode and Extensions..." \
    "${DOTFILES}/lib/install/install_vscode.sh" \
    "Installed VSCode and Extensions."

#######################################################################
# Phase 2: configuration and initialization

show_spinner "Setting up Bitwarden services..." \
    "${DOTFILES}/lib/install/install_bitwarden_services.sh" \
    "Set up Bitwarden services."

# setup/update github copilot extension

# initialize bat cache, which is annoying to have to do on first install
bat cache --build

# TODO: install devenv.sh & distrobox
# TODO: adjust sudo permissions
# TODO: tweak bluefin settings and GNOME extensions
# TODO: create ubunto container via distrobox
# TODO: install zed on platforms where it isn't in pkg repository
