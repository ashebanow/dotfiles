#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_fonts" ] && [ "$sourced_install_fonts" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_fonts=true
fi

function install_getnf_if_needed {
    if command -v getnf >&/dev/null; then
        log_debug "getnf already installed"
        return
    fi
    gum spin --title "Installing getnf..." -- \
        curl -fsSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh | bash -s -- --silent
    log_info "Installed getnf."
}

# Install everything in Fontfile, which has the format "command font-name".
#
# Valid examples of commands:
#   cask cask-name          # homebrew cask, mac only
#   arch package_name       # ignored if non-arch derivative
#   apt package_name        # ignored if non-debian derivative
#   rpm package_name        # ignored if non-fedora derivative
#   getnf font-name         # use on any platform, recommended.
#
# Note that not all commands work on all platforms. If we get a request
# for a command that isn't supported, we ignore that line and keep going,
# SILENTLY.
function install_fonts {
    function internal_install_fonts() {
        readarray -t font_specs <"${DOTFILES}/Fontfile"
        for spec in "${font_specs[@]}"; do
            # split the font_spec into <command,font> pairs separated by whitespace
            IFS=' ' read -r command font <<<"$spec"
            log_debug "Fontfile command: command: $command font: $font"

            case "$command" in
            cask)
                # ignored if not a darwin system
                if is_darwin; then
                    brew install --cask -y "$font"
                fi
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
                gum spin --title "Installing font $font..." -- getnf -U -i "$font"
                # getnf -U -i "$font"
                ;;

            *)
                log_error "Unknown font command: $command"
                ;;
            esac
        done
    }

    install_getnf_if_needed
    internal_install_fonts
}

if [ -z "$sourced_install_fonts" ]; then
    install_fonts
fi
