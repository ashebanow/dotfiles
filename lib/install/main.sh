#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

#######################################################################
# Phase 1: install universal packages and apps
show_spinner \
    "Installing required prerequisites..." \
    "${DOTFILES}/lib/install/prerequisites.sh" \
    "Installed required prerequisites."

# show_spinner \
# 	"Installing nix..." \
#   "${DOTFILES}/lib/install/nix.sh"
# 	"Installed nix."

show_spinner "Installing fonts..." \
    "${DOTFILES}/lib/install/fonts.sh" \
    "Installed fonts..."

show_spinner "Installing Claude Code..." \
    "${DOTFILES}/lib/install/claude_code.sh" \
    "Installed Claude Code."

show_spinner "Installing Zed..." \
    "${DOTFILES}/lib/install/zed.sh" \
    "Installed Zed."

show_spinner "Installing VSCode and Extensions..." \
    "${DOTFILES}/lib/install/vscode.sh" \
    "Installed VSCode and Extensions."

#######################################################################
# Phase 2: configuration and initialization

show_spinner "Setting up Bitwarden services..." \
    "${DOTFILES}/lib/install/bitwarden_services.sh" \
    "Set up Bitwarden services."

# setup/update github copilot extension

# initialize bat cache, which is annoying to have to do on first install
log_info "Initializing bat cache..."
bat cache --build > /dev/null 2>&1

# TODO: install devenv.sh & distrobox
# TODO: adjust sudo permissions
# TODO: tweak bluefin settings and GNOME extensions
# TODO: create ubunto container via distrobox
# TODO: install zed on platforms where it isn't in pkg repository
