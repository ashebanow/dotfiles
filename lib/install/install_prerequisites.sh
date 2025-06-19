#!/bin/bash

# setup common to all install scripts, but note that gum-dependent
# functions in this file won't work until gum gets installed, and
# thus should be avoided here.
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if is_sourced; then
  if [ -n $sourced_install_prerequisites ]; then
    return;
  fi
  sourced_install_prerequisites=true
fi

#--------------------------------------------------------------------
# CHECK FOR REQUIRED TOOLS
#--------------------------------------------------------------------

need_brew=false
need_gum=false
need_bitwarden=false

function checkNeededPrerequisites() {
  if ! command -v brew >/dev/null 2>&1; then
    need_brew=true
  fi

  if ! command -v gum >/dev/null 2>&1; then
    need_gum=true
  fi

  if ! command -v bw >/dev/null 2>&1; then
    need_bitwarden=true
  fi
}

#--------------------------------------------------------------------
# INSTALL FUNCTIONS
#--------------------------------------------------------------------

function install_homebrew_if_needed {
  if ! $need_brew; then
    return
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

function darwin_install_bitwarden {
  brew update
  brew install --upgrade --cask bitwarden
  brew install --upgrade bitwarden-cli
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
  sudo apt update && sudo apt install bitwarden bitwarden-cli
}

function fedora_install_bitwarden {
  sudo flatpak install bitwarden

  install_homebrew_if_needed
  brew update
  brew install --upgrade bitwarden-cli
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
      fedora_install_bitwarden
    else
      # give up for now
      echo "Unsupported OS, don't know its package manager."
      exit 1
    fi
  fi

  echo "Be sure to setup your account(s) and vault(s) in bitwarden."
  echo "To do so, run 'bw login' in your terminal to login. Once the "
  echo "dots are installed, you will be asked to login automatically"
  echo "if needed."
}

function install_gum_if_needed() {
  if ! command -v gum >& /dev/null; then
    brew install --upgrade gum
  fi
}

#--------------------------------------------------------------------
# CORE LOGIC
#--------------------------------------------------------------------

function install_prerequisites() {
  checkNeededPrerequisites
  install_homebrew_if_needed
  install_gum_if_needed
  install_bitwarden_if_needed
}

if ! is_sourced; then
  install_prerequisites
fi
