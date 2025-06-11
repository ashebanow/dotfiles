#!/usr/bin/env bash

# Make sure the script gets run if any of our data files change.
# Note that file refs are relative to the Chezmoi Home dir.
# ../Brewfile hash: {{ include "../Brewfile" | sha256sum }}
# ../Brewfile-darwin hash: {{ include "../Brewfile-darwin" | sha256sum }}
# ../Flatfile hash: {{ include "../Flatfile" | sha256sum }}
# ../Fontfile hash: {{ include "../Fontfile" | sha256sum }}
# ../VSExtensionsFile hash: {{ include "../VSExtensionsFile" | sha256sum }}

# setup common to all install scripts
source "$(dirname "${BASH_SOURCE[0]}")/install_common.sh"

# install libraries for various things
source "$(dirname "${BASH_SOURCE[0]}")/install_chezmoi.sh"
source "$(dirname "${BASH_SOURCE[0]}")/install_distrobox.sh"
source "$(dirname "${BASH_SOURCE[0]}")/install_flatpak.sh"
source "$(dirname "${BASH_SOURCE[0]}")/install_fonts.sh"

# vscode utilities
source "$(dirname "${BASH_SOURCE[0]}")/../vscode_utils.sh"

show_spinner -- \
	"Installing Flatpak runtime..." \
	internal_install_flatpak \
	"Installed Flatpak runtime..."

show_spinner -- \
	"Installing Flatpak apps..." \
	internal_install_flatpak_apps \
	"Installed Flatpak apps..."

#######################################################################
# Phase 1: install necessary packages for all platforms

if ! command -v brew; then
	log_error "Brew must be preinstalled before initializing these dotfiles"
	log_error "See '{{- .chezmoi.config.sourceDir -}}/bin/install-prerequisites.sh' for more info"
	exit 1
fi

gum spin --spinner meter --title "Installing brews..." -- \
	brew bundle install --upgrade --file="{{- .chezmoi.config.sourceDir -}}/Brewfile"
log_info "Installed brews..."

#######################################################################
# Phase 2: install platform specific bits

# {{- if eq .chezmoi.os "linux" -}}

# {{- if (or
#          (and
#            (hasKey .chezmoi.osRelease "idLike")
#            (eq .chezmoi.osRelease.idLike "arch"))
#          (eq .chezmoi.osRelease.id "arch")) -}}

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

install_flatpak_apps

# {{- end }}

# {{- else if eq .chezmoi.os "darwin" -}}

# gum spin --spinner meter --title "Installing Mac-only Brews and Casks..." -- \
# brew bundle install --upgrade --file="{{- .chezmoi.config.sourceDir -}}/Brewfile-darwin"
# log_info "Installed Mac-only Brews and Casks."

# {{- else }}

# log_error "unknown os: {{- .chezmoi.os  }}"
# exit 1

# {{ end }}

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
