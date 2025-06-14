#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

source "${DOTFILES}/lib/install/install_arch.sh"
source "${DOTFILES}/lib/install/install_homebrew.sh"

# make sure we only source this once.
if is_sourced; then
  if [ -n $sourced_install_bitwarden ]; then;
    return;
  fi
  sourced_install_bitwarden=true;
fi

function darwin_install_bitwarden {
  install_homebrew_if_needed
  brew update
  brew install --cask bitwarden
  brew install bitwarden-cli
}

function arch_install_bitwarden {
  install_yay_if_needed

  # Check out the repo, build, and install
  yay -Sqy --needed --noconfirm bitwarden bitwarden-cli
}

function debian_install_bitwarden {
  # Install bitwarden:
  sudo apt update && sudo apt install bitwarden bitwarden-cli
}

function fedora_install_bitwarden {
  install_homebrew_if_needed
  sudo flatpak install bitwarden
  brew install bitwarden-cli
}

function install_bitwarden_if_needed {
  if ! command -v bw; then
    return
  fi

  if $is_darwin; then
    darwin_install_bitwarden
  else
    # commands to install password-manager-binary on Linux
    if is_arch_like; then
      arch_install_bitwarden
    elif is_debian_like; then
      debian_install_bitwarden
    elif is_fedora_like
      fedora_install_bitwarden
    else
      # give up for now
      echo "Unsupported OS, don't know its package manager."
      exit 1
    fi
  fi
}

if !is_sourced; then
  install_bitwarden_if_needed
fi
