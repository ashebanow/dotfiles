#!/usr/bin/env bash

# make sure we only source this once.
if [ -n $sourced_install_main ]; then
  return;
fi
sourced_install_main=true

# Make sure the script gets run if any of our data files change.
# Note that file refs are relative to the Chezmoi Home dir.
# ../Brewfile hash: {{ include "../Brewfile" | sha256sum }}
# ../Brewfile-darwin hash: {{ include "../Brewfile-darwin" | sha256sum }}
# ../Flatfile hash: {{ include "../Flatfile" | sha256sum }}
# ../Flatfile hash: {{ include "../Flatfile-gaming" | sha256sum }}
# ../Fontfile hash: {{ include "../Fontfile" | sha256sum }}
# ../VSExtensionsFile hash: {{ include "../VSExtensionsFile" | sha256sum }}

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# source our library of install modules.
source "${DOTFILES}/lib/install/install_arch.sh"
source "${DOTFILES}/lib/install/install_bitwarden.sh"
source "${DOTFILES}/lib/install/install_chezmoi.sh"
source "${DOTFILES}/lib/install/install_claude_code.sh"
source "${DOTFILES}/lib/install/install_distroboxes.sh"
source "${DOTFILES}/lib/install/install_flatpaks.sh"
source "${DOTFILES}/lib/install/install_fonts.sh"
source "${DOTFILES}/lib/install/install_github.sh"
source "${DOTFILES}/lib/install/install_gum.sh"
source "${DOTFILES}/lib/install/install_homebrew.sh"
source "${DOTFILES}/lib/install/install_nix.sh"
source "${DOTFILES}/lib/install/install_vscode.sh"
source "${DOTFILES}/lib/install/install_zed.sh"

#######################################################################
# Phase 1: install universal packages and apps

# NOTE: we can't use spinner here because gum may not be installed yet...
if ! command -v gum; then
  echo -n "Installing gum..."
  install_gum_if_needed
  echo "\rInstalled gum."
fi

show_spinner -- \
    "Installing homebrew..." \
	install_homebrew_if_needed \
	"Installed homebrew."

show_spinner -- \
    "Installing homebrew packages..." \
	install_homebrew_packages \
	"Installed homebrew packages."

show_spinner -- \
	"Installing bitwarden..." \
	install_bitwarden_if_needed \
	"Installed bitwarden."

show_spinner -- \
	"Installing nix..." \
	install_nix_if_needed \
	"Installed nix."

show_spinner -- \
	"Installing Flatpak runtime..." \
	install_flatpak_if_needed \
	"Installed Flatpak runtime."

show_spinner -- \
	"Installing Flatpak apps..." \
	install_flatpak_apps \
	"Installed Flatpak apps."

#######################################################################
# Phase 2: install platform specific bits

if is_arch_like; then
  update_arch_if_needed
  install_arch_packages
fi

if is_darwin; then
  show_spinner -- "Installing Mac-only Brews and Casks..." \
    install_mac_only_homebrew_packages \
    "Installed Mac-only Brews and Casks."
fi

show_spinner -- "Installing VSCode Extensions..." \
    "${DOTFILES}/lib/install/install_vscode.sh" \
    "Installed VSCode Extensions."

show_spinner -- "Installing fonts..." \
    "${DOTFILES}/lib/install/install_fonts.sh" \
    "Installed fonts..."

#######################################################################
# Phase 3: configuration and initialization

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
