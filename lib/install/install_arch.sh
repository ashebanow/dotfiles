#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [ -n $sourced_install_arch ]; then
  return;
fi
sourced_install_arch=true

function install_yay_if_needed() {
  sudo pacman -S --needed --noconfirm --noprogressbar git base-devel

  mkdir -p ~/Development/linux
  pushd ~/Development/linux
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si
  popd
}

function update_arch_if_needed() {
  if ! is_arch_like; then
    return;
  fi

  install_yay_if_needed

  yay -Syu
}

function install_arch_packages() {
  if ! is_arch_like; then
    return;
  fi

  readarray -t arch_package_list <"{{- .chezmoi.config.sourceDir -}}/Archfile"
  yay -S --needed --noconfirm --noprogressbar -q "${arch_package_list[@]}"
}

if !is_sourced; then
  update_arch_if_needed
  install_arch_packages
fi
