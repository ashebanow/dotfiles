#!/usr/bin/env bash

# Make sure the script gets run if any of our data files change.
# Note that file refs are relative to the Chezmoi Home dir.
# ../Brewfile hash: {{ include "../Brewfile" | sha256sum }}
# ../Brewfile-darwin hash: {{ include "../Brewfile-darwin" | sha256sum }}
# ../Flatfile hash: {{ include "../Flatfile" | sha256sum }}
# ../Fontfile hash: {{ include "../Fontfile" | sha256sum }}
# ../VSExtensionsFile hash: {{ include "../VSExtensionsFile" | sha256sum }}

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# install libraries for various things
source "${DOTFILES}/lib/install/install_chezmoi.sh"
source "${DOTFILES}/lib/install/install_distrobox.sh"
source "${DOTFILES}/lib/install/install_flatpak.sh"
source "${DOTFILES}/lib/install/install_fonts.sh"
source "${DOTFILES}/lib/install/install_homebrew.sh"

# vscode utilities
source "${DOTFILES}/lib/vscode_utils.sh"

#######################################################################
# Phase 1: install universal packages and apps

show_spinner -- \
    "Installing homebrew..." -- \
	install_homebrew_if_needed \
	"Installed homebrew..."

show_spinner -- \
    "Installing homebrew packages..." -- \
	install_homebrew_packages \
	"Installed homebrew packages..."

show_spinner -- \
	"Installing Flatpak runtime..." \
	install_flatpak_if_needed \
	"Installed Flatpak runtime..."

show_spinner -- \
	"Installing Flatpak apps..." \
	install_flatpak_apps \
	"Installed Flatpak apps..."

#######################################################################
# Phase 2: install platform specific bits

if [[ $ID == "arch" || (-n $ID_LIKE && $ID_LIKE == "arch") ]]; then
  # TODO: split this out into its own file, and put a spinner on it!

  # make sure system is up to date
  log_info "Updating Arch..."
  yay -Syu

  # ideally, there would be a single yay command here, or even
  # a small number of role-themed sets of packages
  log_info "Installing Arch packages..."
  readarray -t arch_package_list <"{{- .chezmoi.config.sourceDir -}}/Archfile"
  for arch_package in "${arch_package_list[@]}"; do
	yay -S --needed --noconfirm "${arch_package}"
  done
fi

if [[ $ID == "darwin" ]]; then
  show_spinner -- "Installing Mac-only Brews and Casks..." \
    install_mac_only_homebrew_packages \
    "Installed Mac-only Brews and Casks."
fi

#######################################################################
# Phase 3: more cross-platform bits get installed and initialized

gum spin --title "Installing VSCode Extensions..." -- ../../../lib/install/install_vscode_extensions.sh
log_info "Installed VSCode Extensions."

gum spin --spinner meter --title "Installing fonts..." -- ../../../lib/install/install_fonts.sh
log_info "Installed fonts..."

# setup/update github copilot extension
# TODO: fix this setup so that it does `gh auth login` and
# `gh auth status -a`.
# if command -v gh; then
# log_info "Installing GitHub CLI Copilot extensions..."
# if $(gh extension list | grep -q gh-copilot); then
# gh extension upgrade github/gh-copilot
# else
# gh extension install github/gh-copilot
# fi
# fi

# initialize bat cache, which is annoying to have to do on first install
bat cache --build

# TODO: install devenv.sh & distrobox
# TODO: adjust sudo permissions
# TODO: tweak bluefin settings and GNOME extensions
# TODO: create ubunto container via distrobox
# TODO: install zed on platforms where it isn't in pkg repository
