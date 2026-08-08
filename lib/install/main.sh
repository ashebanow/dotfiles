#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

#######################################################################
# Phase 1: prerequisites
#
# CLI tools on the nix-managed hosts (macOS via nix-darwin + home-manager,
# servers via NixOS) all come from the nix flake — see modules/features/
# cli-*.nix in the lumquat nix-config. Homebrew on macOS is limited to the
# casks declared in the flake's homebrew.casks. prerequisites.sh only fills
# Linux distro gaps and macOS-specific bits (Xcode) that nix doesn't cover,
# so this is the only package-install phase left.
show_spinner \
    "Installing required prerequisites..." \
    "${DOTFILES}/lib/install/prerequisites.sh" \
    "Installed required prerequisites."

#######################################################################
# Phase 2: configuration and initialization

show_spinner "Setting up Bitwarden services..." \
    "${DOTFILES}/lib/install/bitwarden_services.sh" \
    "Set up Bitwarden services."

# initialize bat cache, which is annoying to have to do on first install
log_info "Initializing bat cache..."
bat cache --build > /dev/null 2>&1
