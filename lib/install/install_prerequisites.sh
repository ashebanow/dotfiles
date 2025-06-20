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
need_node=false
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

    if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
        need_node=true
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
# INSTALL NODE & NPM
#--------------------------------------------------------------------

function setup_npm_paths {
    local npm_bin_dir="\$HOME/.npm-global/bin"

    # Update .bashrc if it exists and doesn't already contain the path
    if [[ -f ~/.bashrc ]] && ! grep -q ".npm-global/bin" ~/.bashrc; then
        echo "$npm_bin_dir:\$PATH" >>~/.bashrc
    fi

    # Update .zshrc if it exists and doesn't already contain the path
    if [[ -f ~/.zshrc ]] && ! grep -q ".npm-global/bin" ~/.zshrc; then
        echo "$npm_bin_dir:\$PATH" >>~/.zshrc
    fi

    # Update fish config if it exists and doesn't already contain the path
    if [[ -f "/.config/fish/config.fish" ]] && ! grep -q ".npm-global/bin" ~/.config/fish/config.fish; then
        echo "fish_add_path $npm_bin_dir" >>~/.config/fish/config.fish
    fi

    # Update current session PATH. its ok if this gets toasted later,
    # since the shell init script(s) will add it more permanently.
    export PATH="$npm_bin_dir:$PATH"
}

function setup_npm_global_directory {
    # Create ~/.npm-global directory
    mkdir -p ~/.npm-global

    # Configure npm to use the new directory
    npm config set prefix ~/.npm-global
}

function migrate_existing_npm_packages {
    # Save existing global packages before migration
    if command -v npm >/dev/null 2>&1; then
        echo "Saving existing global npm packages list..."
        npm list -g --depth=0 >~/npm-global-packages-backup.txt 2>/dev/null || true

        # Extract package names (excluding npm itself and path info)
        if [[ -f ~/npm-global-packages-backup.txt ]]; then
            grep -E '^[├└]─' ~/npm-global-packages-backup.txt |
                sed 's/[├└─ ]//g' |
                sed 's/@[0-9].*//' |
                grep -v '^npm$' >~/npm-packages-to-reinstall.txt 2>/dev/null || true

            # Reinstall packages in new location if any exist
            if [[ -f ~/npm-packages-to-reinstall.txt ]] && [[ -s ~/npm-packages-to-reinstall.txt ]]; then
                echo "Reinstalling global packages in ~/.npm-global..."
                while read -r package; do
                    [[ -n "$package" ]] && npm install -g "$package" 2>/dev/null || true
                done <~/npm-packages-to-reinstall.txt
            fi
        fi
    fi
}

function install_node_if_needed {
    if ! $need_node; then
        # Check if npm is using ~/.npm-global prefix
        local current_prefix
        current_prefix=$(npm config get prefix 2>/dev/null || echo "")
        if [[ "$current_prefix" != "$HOME/.npm-global" ]]; then
            echo "Node/npm found but not using ~/.npm-global prefix. Setting up..."
            setup_npm_global_directory
            setup_npm_paths
            migrate_existing_npm_packages
        fi
        return
    fi

    echo "Installing Node.js and npm..."

    # Set up the npm global directory structure BEFORE installing Node/npm
    # This way npm will use the correct prefix from the start
    mkdir -p ~/.npm-global

    if $is_darwin; then
        install_homebrew_if_needed
        brew install node
    else
        if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
            sudo pacman -S --needed --noconfirm nodejs npm
        elif [[ $ID == *"ubuntu"* || $ID == *"debian"* || $ID_LIKE == *"debian"* ]]; then
            # Install Node.js 20.x LTS (or whatever the current lts is)
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif [[ $ID == *"fedora"* || $ID_LIKE == *"fedora"* ]]; then
            if command -v dnf5; then
                sudo dnf5 install nodejs npm
            else
                sudo dnf install nodejs npm
            fi
        else
            echo "Unsupported OS for Node.js installation."
            exit 1
        fi
    fi

    # Configure npm to use ~/.npm-global immediately after installation
    npm config set prefix ~/.npm-global
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
    if command -v bw >&/dev/null; then
        return
    fi

    if [[ $ID == *"arch"* || $ID_LIKE == *"arch"* ]]; then
        arch_install_bitwarden_cli
    else
        install_homebrew_if_needed
        brew update
        brew install bitwarden-cli
    fi
}

#--------------------------------------------------------------------
# INSTALL BITWARDEN DESKTOP
#--------------------------------------------------------------------

# Bitwarden Desktop installation functions
function darwin_install_bitwarden_desktop {
    brew update
    brew install --cask bitwarden
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
    brew install gum
}

#--------------------------------------------------------------------
# CORE LOGIC
#--------------------------------------------------------------------

function install_prerequisites() {
    checkNeededPrerequisites
    install_homebrew_if_needed
    install_flatpak_if_needed
    install_node_if_needed
    install_gum_if_needed
    install_bitwarden_if_needed
}

if [ -z "$sourced_install_prerequisites" ]; then
    install_prerequisites
fi
