#!/usr/bin/env bash

# setup common to all install scripts, but note that gum-dependent
# functions in this file won't work until gum gets installed, and
# thus should be avoided here.
source "${DOTFILES}/lib/common/all.sh"

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
need_keyring_tools=false
need_tailscale=false
need_jq=false

function checkNeededPrerequisites() {
    if ! pkg_installed "brew"; then
        need_brew=true
    fi

    if ! pkg_installed "flatpak"; then
        need_flatpak=true
    fi

    if ! pkg_installed "gum"; then
        need_gum=true
    fi

    if ! pkg_installed "jq"; then
        need_jq=true
    fi

    # Bitwarden CLI has different package names on different platforms
    declare -A bw_packages=(
        ["darwin"]="bitwarden-cli"
        ["arch"]="bitwarden-cli"
        ["fedora"]="bitwarden-cli"
    )
    if ! pkg_installed "bw" bw_packages; then
        need_bitwarden=true
    fi

    if ! pkg_installed "node" || ! pkg_installed "npm"; then
        need_node=true
    fi

    # Check for keyring tools (Linux only)
    if ! $is_darwin; then
        # secret-tool package mapping
        declare -A secret_tool_packages=(
            ["arch"]="libsecret"
            ["debian"]="libsecret-tools"
            ["fedora"]="libsecret"
        )
        if ! pkg_installed "secret-tool" secret_tool_packages; then
            need_keyring_tools=true
        fi

        # zenity is optional for GUI environments
        if [[ -n "${DISPLAY:-}" ]] && ! pkg_installed "zenity"; then
            need_keyring_tools=true
        fi
    fi

    # Check for Tailscale
    if ! pkg_installed "tailscale"; then
        need_tailscale=true
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
        if is_arch_like; then
            sudo pacman -S --needed --noconfirm nodejs npm
        elif is_debian_like; then
            # Install Node.js 20.x LTS (or whatever the current lts is)
            curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
            sudo apt-get install -y nodejs
        elif is_fedora_like; then
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

    if is_arch_like; then
        sudo pacman -S flatpak
    elif is_debian_like; then
        sudo apt install flatpak
    elif is_fedora_like; then
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
    declare -A bw_packages=(
        ["darwin"]="bitwarden-cli"
        ["arch"]="bitwarden-cli"
        ["fedora"]="bitwarden-cli"
    )
    if pkg_installed "bw" bw_packages; then
        return
    fi

    declare -A bw_packages=(
        ["darwin"]="bitwarden-cli"
        ["arch"]="bitwarden-cli"
        ["fedora"]="bitwarden-cli"
    )

    if is_arch_like; then
        arch_install_bitwarden_cli
    else
        pkg_install "bw" bw_packages
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
        if is_arch_like; then
            arch_install_bitwarden_desktop
        elif is_debian_like || is_fedora_like; then
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
# INSTALL KEYRING TOOLS
#--------------------------------------------------------------------

function install_keyring_tools_if_needed() {
    if $is_darwin; then
        # macOS has keychain built-in
        return
    fi

    if ! $need_keyring_tools; then
        return
    fi

    # Install secret-tool
    declare -A secret_tool_packages=(
        ["arch"]="libsecret"
        ["debian"]="libsecret-tools"
        ["fedora"]="libsecret"
    )
    pkg_install "secret-tool" secret_tool_packages

    # Install zenity (same name across platforms)
    pkg_install "zenity"
}

#--------------------------------------------------------------------
# INSTALL GUM
#--------------------------------------------------------------------

function install_gum_if_needed() {
    if ! $need_gum; then
        return
    fi
    pkg_install "gum"
}

#--------------------------------------------------------------------
# INSTALL JQ
#--------------------------------------------------------------------

function install_jq_if_needed() {
    if ! $need_jq; then
        return
    fi
    pkg_install "jq"
}

#--------------------------------------------------------------------
# INSTALL TAILSCALE
#--------------------------------------------------------------------

function install_tailscale_if_needed() {
    if ! $need_tailscale; then
        return
    fi

    log_info "Installing Tailscale..."

    # Define Tailscale repository configurations
    declare -A tailscale_repos=(
        ["debian"]='{
            "base_url": "https://pkgs.tailscale.com/stable/debian",
            "version_name": "auto",
            "key_url": "https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg"
        }'
        ["fedora"]="https://pkgs.tailscale.com/stable/fedora/tailscale.repo"
    )
    
    # Define pre-install hooks
    declare -A tailscale_pre=(
        ["darwin"]="install_homebrew_if_needed"
    )
    
    # Define post-install hooks
    declare -A tailscale_post=(
        ["arch"]="sudo systemctl enable --now tailscaled"
        ["fedora"]="sudo systemctl enable --now tailscaled"
        ["darwin"]="brew services start tailscale"
    )
    
    # Install using the unified pkg_install function
    pkg_install "tailscale" "" tailscale_repos tailscale_pre tailscale_post

    log_info "Tailscale installed successfully"
}

function activate_tailscale() {
    # Automatically detect headless mode based on system environment
    local headless_mode="false"
    if $is_virtualized || [[ -z "${DISPLAY:-}" ]]; then
        headless_mode="true"
    fi

    # Check if Tailscale is already connected
    if tailscale status >/dev/null 2>&1 && tailscale status | grep -q "logged in"; then
        log_info "Tailscale is already activated and connected"
        return 0
    fi

    log_info "Activating Tailscale..."

    if [[ "$headless_mode" == "true" ]]; then
        # Headless mode using Bitwarden auth key
        log_info "Using headless mode with Bitwarden auth key..."

        # Get auth key from Bitwarden
        local auth_key
        auth_key=$(bw get password "tailscale-homelab-ephemeral" 2>/dev/null)

        if [[ -z "$auth_key" ]]; then
            log_error "Failed to retrieve Tailscale auth key from Bitwarden"
            log_error "Please ensure 'tailscale-homelab-ephemeral' exists in Bitwarden"
            return 1
        fi

        # Create secure temporary file for auth key
        local temp_key_file
        temp_key_file=$(mktemp)
        chmod 600 "$temp_key_file"
        
        # Write auth key to temporary file
        echo "$auth_key" > "$temp_key_file"
        
        # Use auth key file for headless setup
        sudo tailscale up --authkey="file:$temp_key_file" --ssh --accept-routes
        local result=$?
        
        # Clean up temporary file
        rm -f "$temp_key_file"

        if [[ $result -eq 0 ]]; then
            log_info "Tailscale activated successfully in headless mode"
        else
            log_error "Failed to activate Tailscale in headless mode"
            return 1
        fi
    else
        # Interactive mode
        log_info "Activating Tailscale in interactive mode..."
        log_info "This will open a browser for authentication"

        sudo tailscale up --ssh --accept-routes
        if [[ $? -eq 0 ]]; then
            log_info "Tailscale activation initiated"
            log_info "Note: Activation won't be complete until a Tailscale admin approves this device"
            log_info "Have an admin approve the new device in the admin console."
        else
            log_error "Failed to initiate Tailscale activation"
            return 1
        fi
    fi
}

#--------------------------------------------------------------------
# CORE LOGIC
#--------------------------------------------------------------------

function install_prerequisites() {
    checkNeededPrerequisites
    install_homebrew_if_needed
    install_flatpak_if_needed
    install_node_if_needed
    install_keyring_tools_if_needed
    install_jq_if_needed
    install_gum_if_needed
    install_bitwarden_if_needed
    install_tailscale_if_needed
}

if [ -z "$sourced_install_prerequisites" ]; then
    install_prerequisites
fi
