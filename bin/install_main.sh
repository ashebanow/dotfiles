#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# source our library of install modules.
source "${DOTFILES}/lib/install_prerequisites.sh"
source "${DOTFILES}/lib/install/install_arch.sh"
source "${DOTFILES}/lib/install/install_chezmoi.sh"
source "${DOTFILES}/lib/install/install_claude_code.sh"
source "${DOTFILES}/lib/install/install_distroboxes.sh"
source "${DOTFILES}/lib/install/install_flatpaks.sh"
source "${DOTFILES}/lib/install/install_fonts.sh"
source "${DOTFILES}/lib/install/install_homebrew.sh"
source "${DOTFILES}/lib/install/install_github.sh"
source "${DOTFILES}/lib/install/install_nix.sh"
source "${DOTFILES}/lib/install/install_vscode.sh"
source "${DOTFILES}/lib/install/install_zed.sh"

#######################################################################
# Phase 1: install universal packages and apps

# install arch packages here if appropriate.
# It is important that this be done early so that
# homebrew knows we already have commands installed.
# TODO: do the same for debian-like systems, and for
# mutable fedora distributions.
# TODO: use show_spinner function
if is_arch_like; then
  update_arch_if_needed
  install_arch_packages
fi

show_spinner -- \
    "Installing homebrew packages..." \
	install_homebrew_packages \
	"Installed homebrew packages."

# show_spinner -- \
# 	"Installing nix..." \
# 	install_nix_if_needed \
# 	"Installed nix."

if is_darwin; then
  show_spinner -- "Installing Mac-only Brews and Casks..." \
    install_mac_only_homebrew_packages \
    "Installed Mac-only Brews and Casks."
fi

show_spinner -- \
	"Installing Flatpak runtime if needed..." \
	install_flatpak_if_needed \
	"Installed Flatpak runtime if needed."

show_spinner -- \
	"Installing Flatpak apps..." \
	install_flatpak_apps \
	"Installed Flatpak apps."

show_spinner -- "Installing VSCode Extensions..." \
    "${DOTFILES}/lib/install/install_vscode.sh" \
    "Installed VSCode Extensions."

show_spinner -- "Installing fonts..." \
    "${DOTFILES}/lib/install/install_fonts.sh" \
    "Installed fonts..."

#######################################################################
# Phase 2: configuration and initialization

# setup/update github copilot extension

# initialize bat cache, which is annoying to have to do on first install
bat cache --build

# TODO: install devenv.sh & distrobox
# TODO: adjust sudo permissions
# TODO: tweak bluefin settings and GNOME extensions
# TODO: create ubunto container via distrobox
# TODO: install zed on platforms where it isn't in pkg repository
