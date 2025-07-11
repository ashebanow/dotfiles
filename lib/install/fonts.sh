#!/usr/bin/env bash

# setup common to all install scripts
# Auto-detect DOTFILES if not set
if [[ -z "${DOTFILES:-}" ]]; then
    DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    export DOTFILES
fi
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
    if pkg_installed "getnf"; then
        log_debug "getnf already installed"
        return
    fi
    log_info "Installing getnf..."
    if command -v gum >/dev/null 2>&1; then
        gum spin --title "Installing getnf..." -- bash -c "curl -fsSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh | bash -s -- --silent"
    else
        bash -c "curl -fsSL https://raw.githubusercontent.com/getnf/getnf/main/install.sh | bash -s -- --silent"
    fi
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
        # Use bash 3.2 compatible array reading (readarray not available)
        font_specs=()
        while IFS= read -r line; do
            font_specs+=("$line")
        done < "${DOTFILES}/packages/Fontfile"
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
                log_info "Installing font $font if needed"
                # Capture getnf output and exit code
                local output
                local exit_code
                output=$(getnf -U -i "$font" 2>&1)
                exit_code=$?
                
                # Check if getnf failed
                if [[ $exit_code -ne 0 ]]; then
                    log_error "Failed to install font $font: $output"
                    return 1
                fi
                
                # Filter out "already up to date" message but show other output
                echo "$output" | grep -v "All installed Nerd Fonts are up to date" || true
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
