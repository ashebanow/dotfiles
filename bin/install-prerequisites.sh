#!/bin/bash

# This script installs the apps and tools required for chezmoi setup
# to function. # It is intended to be run via chezmoi's
# hooks.read-source-state.pre # mechanism, which is why it isn't a
# standard chezmoi template/script.
#
# NOTE: this script will run every time you run a `chezmoi apply` command,
# so its important that it be fast in the common case and idempotent.

# setup common to all install scripts
source "install_common.sh"

#--------------------------------------------------------------------
# CHECK FOR HOMEBREW
#--------------------------------------------------------------------

# check for existence of prerequisites
need_brew=false
if ! command -v brew >/dev/null 2>&1; then
  need_brew=true
fi

#--------------------------------------------------------------------
# CHECK FOR BITWARDEN
#--------------------------------------------------------------------

need_bitwarden=false
if ! command -v bw >/dev/null 2>&1; then
  need_bitwarden=true
fi

#--------------------------------------------------------------------
# CHECK FOR NIX
#--------------------------------------------------------------------
need_nix=false
# if ! command -v nix >/dev/null 2>&1; then
# need_nix=true
# fi

need_nix_conf_update=false
nix_conf_src=$(dirname "$(realpath "$0")")/../home/private_dot_local/share/nix/etc-nix-nix.conf
nix_conf_dest=/etc/nix/nix.conf

function need_nix_conf_update {
    # NOTE: turned off for now because the bazzite/bluefin distros
    # only support nix via distrobox. So the longer term solution
    # is to setup a distrobox for our development needs, with nix,
    # devenv and such installed there.
    #
    # if dest file doesn't exist, or is different from source file,
    # then the dest needs updating
    # if [[ ! -f "$nix_conf_dest" ]]; then
      # return 0
    # elif ! diff "$nix_conf_src" "$nix_conf_dest" >/dev/null 2>&1; then
      # return 0
    # fi
    return 1
}

# set up /etc/nix/nix.conf from ~/.local/share/nix/etc-nix-nix.conf, but only if it
# missing or different.
function install_nix_conf_update_if_needed {
  if ! need_nix_conf_update; then
    return
  fi
  # TODO: we need to handle the /etc/nix/nix.conf.custom case
  echo "Need sudo access to update $nix_conf_dest..."
  sudo cp "$nix_conf_src" "$nix_conf_dest"
}

#--------------------------------------------------------------------
# CHECK FOR gum
#--------------------------------------------------------------------
need_gum=false
if ! command -v gum >/dev/null 2>&1; then
  need_gum=true
fi

#--------------------------------------------------------------------
# INSTALL FUNCTIONS
#--------------------------------------------------------------------

function install_homebrew_if_needed {
  if ! $need_brew; then
    return
  fi

  if ! $is_darwin; then
    # commands to install password-manager-binary on Linux
    # but Arch doesn't need homebrew since AUR + nix is more than
    # sufficient
    if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
      return
    fi
   fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

function darwin_install_bitwarden {
  brew update
  brew install --cask bitwarden
  brew install bitwarden-cli
}

function arch_install_bitwarden {
  # Make sure yay is installed
  if ! command -v yay >/dev/null 2>&1; then
    echo "Installing yay..."
    sudo pacman -Sq --needed --noconfirm git base-devel >/dev/null 2>&1
    pushd /tmp
    rm -rf /tmp/yay
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si
    popd
  fi

  # Check out the repo, build, and install
  yay -Sqy --needed --noconfirm bitwarden bitwarden-cli
}

function ubuntu_install_bitwarden {
  # Install bitwarden:
  sudo apt update && sudo apt install bitwarden bitwarden-cli
}

function fedora_install_bitwarden {
  sudo flatpak install bitwarden
  brew install bitwarden-cli
}

function install_bitwarden_if_needed {
  if ! $need_bitwarden; then
    return
  fi

  if $is_darwin; then
    darwin_install_bitwarden
  else
    # commands to install password-manager-binary on Linux
    if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
      arch_install_bitwarden
    elif [[ $ID == *"ubuntu"* || $ID_LIKE == *"ubuntu"* ]]; then
      ubuntu_install_bitwarden
    elif [[ $ID == *"fedora"* || $ID_LIKE == *"fedora"* ]]; then
      install_homebrew_if_needed
      fedora_install_bitwarden
    else
      # give up for now
      echo "Unsupported OS, don't know its package manager."
      exit 1
    fi
  fi

  echo "Be sure to setup your account(s) and vault(s) in bitwarden."
  echo "Now run 'bw login' in your terminal to login. Once the dots are"
  echo "installed, you will be asked to login automatically if needed."
}

#--------------------------------------------------------------------
# CORE LOGIC
#--------------------------------------------------------------------

# exit immediately if all prerequisites are installed already
if ! ($need_brew || $need_bitwarden || $need_nix || $need_gum || need_nix_conf_update); then
    exit 0
fi

# TODO: set hostname of machine

install_homebrew_if_needed
install_bitwarden_if_needed

# install nix
if $need_nix; then
  echo "Installing Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
fi
install_nix_conf_update_if_needed

if $need_gum; then
  brew install gum
fi

# TODO: setup ssh
