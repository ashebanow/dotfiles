#!/usr/bin/env bash

# Make sure the script gets run if any of our data files change.
# Note that file refs are relative to the Chezmoi Home dir.
# ../Brewfile hash: {{ include "../Brewfile" | sha256sum }}
# ../Brewfile-darwin hash: {{ include "../Brewfile-darwin" | sha256sum }}
# ../Flatfile hash: {{ include "../Flatfile" | sha256sum }}
# ../Fontfile hash: {{ include "../Fontfile" | sha256sum }}
# ../VSExtensionsFile hash: {{ include "../VSExtensionsFile" | sha256sum }}

# setup common to all install scripts
source "install_common.sh"

# vscode utilities
source "../vscode_utils.sh"

#######################################################################
# Utility functions

function log_debug() {
  gum log --structured --level debug "$@"
}

function log_info() {
  gum log --structured --level info "$@"
}

function log_warning() {
  gum log --structured --level warning "$@"
}

function log_error() {
  gum log --structured --level error "$@"
}

function internal_is_vscode_extension_installed() {
  local extension="$1"

  for installed_extension in "${installed_vscode_extensions[@]}"; do
    if [ "$installed_extension" == "$extension" ]; then
      log_debug "$extension is already installed, skipping."
      return 1
    fi
  done
  return 0
}

function internal_install_vscode_extensions() {
  vscode_binary_path="$(find_vscode_binary)"
  if [ $? -ne 0 ] || [ -z "$vscode_binary_path" ]; then
    log_error "You must have the VSCode 'code' or equivalent binary in your PATH."
    exit 1
  fi

  declare -a installed_vscode_extensions
  readarray -t installed_vscode_extensions < <($vscode_binary_path --list-extensions)

  readarray -t vscode_extensions_list < "{{- .chezmoi.config.sourceDir -}}/VSExtensionsFile"
  for vscode_extension in "${vscode_extensions_list[@]}"; do
      if internal_is_vscode_extension_installed "$vscode_extension"; then
        "$vscode_binary_path" --install-extension "$vscode_extension" --force
      fi
  done
}

function install_vscode_extensions() {
  gum spin --title "Installing VSCode Extensions..." -- internal_install_vscode_extensions
  log_info "Installed VSCode Extensions."
}

function install_getnf_if_needed {
  if command -v getnf; then
    return;
  fi
  gum spin --title "Installing getnf..." -- \
    curl -fsSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh | bash -s -- --silent
  log_info "Installed getnf."
}

# Install everything in Fontfile, which has the format "source font-name".
#
# Valid examples of sources:
#   cask cask-name          # homebrew cask, mac only
#   arch package_name       # ignored if non-arch derivative
#   apt package_name        # ignored if non-debian derivative
#   rpm package_name        # ignored if non-fedora derivative
#   getnf font-name         # use on any platform, recommended.
#
# Note that not all sources work on all platforms. If we get a request
# for a source that isn't supported, we ignore that line and keep going,
# SILENTLY.
function install_fonts {
  install_getnf_if_needed

  function internal_install_fonts() {
    readarray -t font_specs < "{{- .chezmoi.config.sourceDir -}}/Fontfile"
    for spec in "${font_specs[@]}"; do
      # split the font_spec into <source,font> pairs separated by whitespace
      IFS=' ' read -r source font <<< "$spec"

      case "$source" in
        cask)
            # ignored if not a darwin system
{{- if eq .chezmoi.os "darwin" -}}
            brew install --cask -y "$font"
{{ end }}
            ;;

        arch)
            if command -v yay; then
                yay -S --needed -y --noconfirm "$font"
            elif command -v paru; then
                paru -S --needed -y "$font"
            elif command -v pacman; then
                sudo pacman -S --needed -y "$font"
            fi
            ;;

        apt)
            if command -v apt; then
                sudo apt install -q -y "$font"
            fi
            ;;

      rpm)
            if command -v dnf5; then
                sudo dnf5 install -q -y "$font"
            elif command -v dnf; then
                sudo dnf install -q -y "$font"
            fi
            ;;

        getnf)
            # gum spin --title "Installing font $font..." -- getnf -U -i "$font"
            getnf -U -i "$font"
            ;;

        *)
            log_error "Unknown font source: $source"
            ;;
      esac
    done
  }

  gum spin --spinner meter --title "Installing fonts..." -- internal_install_fonts
  log_info "Installed fonts..."
}

function install_flatpak_if_needed {
  if command -v flatpak; then
    # make sure that flathub content is available
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    return;
  fi

  function internal_install_flatpak() {
      if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
        sudo pacman -S flatpak
      elif [[ $ID == *"ubuntu"* || $ID == *"debian"* || $ID_LIKE == *"debian"* ]]; then
        sudo apt install flatpak
      elif [[ $ID == *"fedora"* || $ID_LIKE == *"fedora"* ]]; then
          if command -v dnf5; then
            sudo dnf5 install flatpak
          else
            sudo dnf install flatpak
          fi
      else
        # give up for now
        log_error "Unsupported/unknown linux variant, cannot install flatpak"
        exit 1
      fi

      flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
      flatpak update --appstream
  }

  gum spin --spinner meter --title "Installing Flatpak runtime..." -- internal_install_flatpak
  log_info "Installed Flatpak runtime..."
}

function install_flatpak_apps {
    install_flatpak_if_needed

    function internal_install_flatpak_apps() {
        readarray -t flatpaks_list < "{{- .chezmoi.config.sourceDir -}}/Flatfile"
        flatpak install --user -y --noninteractive --or-update "${flatpaks_list[@]}"
    }

    gum spin --spinner meter --title "Installing Flatpak apps..." -- internal_install_flatpak_apps
    log_info "Installed Flatpak applications..."
}

#######################################################################
# Phase 1: install necessary packages for all platforms

if ! command -v brew ; then
  log_error "Brew must be preinstalled before initializing these dotfiles"
  log_error "See '{{- .chezmoi.config.sourceDir -}}/bin/install-prerequisites.sh' for more info"
  exit 1
fi

gum spin --spinner meter --title "Installing brews..." -- \
  brew bundle install --upgrade --file="{{- .chezmoi.config.sourceDir -}}/Brewfile"
log_info "Installed brews..."

#######################################################################
# Phase 2: install platform specific bits

{{- if eq .chezmoi.os "linux" -}}

{{- if (or
         (and
           (hasKey .chezmoi.osRelease "idLike")
           (eq .chezmoi.osRelease.idLike "arch"))
         (eq .chezmoi.osRelease.id "arch")) -}}

# make sure system is up to date
log_info "Updating Arch..."
yay -Syu

# ideally, there would be a single yay command here, or even
# a small number of role-themed sets of packages
log_info "Installing Arch packages..."
readarray -t arch_package_list < "{{- .chezmoi.config.sourceDir -}}/Archfile"
for arch_package in "${arch_package_list[@]}"; do
  yay -S --needed --noconfirm "${arch_package}"
done

install_flatpak_apps

{{- end }}

{{- else if eq .chezmoi.os "darwin" -}}

gum spin --spinner meter --title "Installing mac-only brews and casks..." -- \
  brew bundle install --upgrade --file="{{- .chezmoi.config.sourceDir -}}/Brewfile-darwin"
log_info "Installed Mac-specific Brews and Casks."

{{- else }}

log_error "unknown os: {{- .chezmoi.os  }}"
exit 1

{{ end }}

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
