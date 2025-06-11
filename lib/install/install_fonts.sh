#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/install_common.sh"

function install_getnf_if_needed {
	if command -v getnf; then
		return
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
		readarray -t font_specs <"{{- .chezmoi.config.sourceDir -}}/Fontfile"
		for spec in "${font_specs[@]}"; do
			# split the font_spec into <source,font> pairs separated by whitespace
			IFS=' ' read -r source font <<<"$spec"

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
}
