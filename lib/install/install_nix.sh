#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [ -n $sourced_install_nix ]; then
  return;
fi
sourced_install_nix=true

need_nix=false
# if ! command -v nix >/dev/null 2>&1; then
#   need_nix=true
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

function install_nix_if_needed() {
  # TODO: move the installer code here from install_prerequisites.
  if $need_nix; then
    echo "Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
  fi
  install_nix_conf_update_if_needed
}

if ! is_sourced; then
  install_nix_if_needed
fi
