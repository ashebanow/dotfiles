#!/bin/bash

# setup common to all install scripts, but note that gum-dependent
# functions in this file won't work until gum gets installed, and
# thus should be avoided here.
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_prerequisites" ] && [ "$sourced_install_prerequisites" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_prerequisites=true
fi

#--------------------------------------------------------------------
# CHECK FOR REQUIRED TOOLS
#--------------------------------------------------------------------

need_brew=false
need_flatpak=false
need_gum=false
need_bitwarden=false

function checkNeededPrerequisites() {
    if ! command -v brew >/dev/null 2>&1; then
        need_brew=true
    fi

    if ! command -v flatpak >/dev/null 2>&1; then
        need_flatpak=true
    fi

    if ! command -v gum >/dev/null 2>&1; then
        need_gum=true
    fi

    if ! command -v bw >/dev/null 2>&1; then
        need_bitwarden=true
    fi
}

#--------------------------------------------------------------------
# INSTALL HOMEBREW
#--------------------------------------------------------------------

function install_homebrew_if_needed {
    if ! $need_brew; then
        return
    fi

    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

#--------------------------------------------------------------------
# INSTALL FLATPAK RUNTIME
#--------------------------------------------------------------------

# Flatpak runtime installation functions
function install_flatpak_if_needed {
    if $is_darwin; then
        return
    fi

    if ! $need_flatpak; then
        # make sure that flathub content is available
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        return
    fi

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

#--------------------------------------------------------------------
# INSTALL BITWARDEN CLI
#--------------------------------------------------------------------

# Bitwarden CLI installation functions
function homebrew_install_bitwarden_cli {
    install_homebrew_if_needed
    brew update
    brew install --upgrade bitwarden-cli
}

function linux_native_install_bitwarden_cli {
    # Create ~/.local/bin if it doesn't exist
    mkdir -p ~/.local/bin

    # Download the latest Bitwarden CLI binary for Linux x64
    local url="https://vault.bitwarden.com/download/?app=cli&platform=linux"
    curl -L "$url" -o ~/.local/bin/bw

    # Make it executable
    chmod +x ~/.local/bin/bw

    # Make sure our destination bin directory is in the path
    fullpath="$(realpath ~/.local/bin)"
    if ! [[ "$PATH" =~ "$fullpath" ]]; then
        PATH="$fullpath:$PATH"
    fi
}

function arch_install_bitwarden_cli {
    # Make sure yay is installed
    if ! command -v yay >/dev/null 2>&1; then
        echo "Installing yay..."
        sudo pacman -Sq --needed --noconfirm git base-devel >/dev/null 2>&1
        pushd /tmp || exit 1
        rm -rf /tmp/yay
        git clone https://aur.archlinux.org/yay.git
        cd yay || exit 1
        makepkg -si
        popd || exit 1
    fi

    yay -Sqy --needed --noconfirm bitwarden-cli
}

function install_bitwarden_cli_if_needed {
    if $is_darwin; then
        homebrew_install_bitwarden_cli
    else
        if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
            arch_install_bitwarden_cli
        elif [[ $ID == *"ubuntu"* || $ID_LIKE == *"ubuntu"* || $ID == *"fedora"* || $ID_LIKE == *"fedora"* ]]; then
            linux_native_install_bitwarden_cli
        else
            echo "Unsupported OS for Bitwarden CLI installation."
            exit 1
        fi
    fi
}

#--------------------------------------------------------------------
# INSTALL BITWARDEN DESKTOP
#--------------------------------------------------------------------

# Bitwarden Desktop installation functions
function darwin_install_bitwarden_desktop {
    brew update
    brew install --upgrade --cask bitwarden
}

function arch_install_bitwarden_desktop {
    # Make sure yay is installed
    if ! command -v yay >/dev/null 2>&1; then
        echo "Installing yay..."
        sudo pacman -Sq --needed --noconfirm git base-devel >/dev/null 2>&1
        pushd /tmp || exit 1 || exit 1
        rm -rf /tmp/yay
        git clone https://aur.archlinux.org/yay.git
        cd yay || exit 1
        makepkg -si
        popd || exit 1
    fi

    yay -Sqy --needed --noconfirm bitwarden
}

function linux_native_install_bitwarden_desktop {
    sudo flatpak install -y bitwarden
}

function install_bitwarden_desktop_if_needed {
    if $is_darwin; then
        darwin_install_bitwarden_desktop
    else
        if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
            arch_install_bitwarden_desktop
        elif [[ $ID == *"ubuntu"* || $ID_LIKE == *"ubuntu"* || $ID == *"fedora"* || $ID_LIKE == *"fedora"* ]]; then
            linux_native_install_bitwarden_desktop
        else
            echo "Unsupported OS for Bitwarden desktop installation."
            exit 1
        fi
    fi
}

function install_bitwarden_if_needed {
    if ! $need_bitwarden; then
        return
    fi

    install_bitwarden_desktop_if_needed
    install_bitwarden_cli_if_needed

    echo "Be sure to setup your account(s) and vault(s) in bitwarden."
    echo "To do so, run 'bw login' in your terminal to login. Once the "
    echo "dots are installed, you will be asked to login automatically"
    echo "if needed."
}

#--------------------------------------------------------------------
# INSTALL GUM
#--------------------------------------------------------------------

function install_gum_if_needed() {
    if ! $need_gum; then
        return
    fi
    brew install --upgrade gum
}

#--------------------------------------------------------------------
# CORE LOGIC
#--------------------------------------------------------------------

function install_prerequisites() {
    checkNeededPrerequisites
    install_homebrew_if_needed
    install_flatpak_if_needed
    install_gum_if_needed
    install_bitwarden_if_needed
}

if [ -z "$sourced_install_prerequisites" ]; then
    install_prerequisites
fi
