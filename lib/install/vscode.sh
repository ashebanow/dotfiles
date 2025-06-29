#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_vscode" ] && [ "$sourced_install_vscode" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_vscode=true
fi

find_vscode_binary() {
    # Check code-server* first, to detect headless easily.
    # We also prioritize insiders versions over regular releases.
    local binary_names=(
        "code-server-insiders"
        "code-server"
        "code-insiders"
        "code"
        "codium"
    )

    # Common installation paths
    local paths=(
        "$HOME/.vscode-server-insiders"
        "$HOME/.vscode-server"
        "$HOME/.vscode-insiders"
        "$HOME/.vscode"
        "/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
        "/usr/bin"
        "/snap/bin"
        "/usr/share/bin"
        "/opt/homebrew/bin"
        "/users/linuxbrew/bin"
    )

    # Check if binary is available in the PATH, return early if found
    for binary in "${binary_names[@]}"; do
        if command -v $binary >/dev/null 2>&1; then
            echo "$(command -v $binary)"
            return 0
        fi
    done

    # Check common paths
    for path in "${paths[@]}"; do
        if [ ! -d "$path" ]; then
            continue
        fi
        for binary in "${binary_names[@]}"; do
            local result=$(find "$path" -path "*/extensions" -prune -o -type f -name "$binary" -print)
            if [ $? -eq 0 ] && [ -n "$result" ]; then
                echo "$result"
                return 0
            fi
        done
    done

    # If not found, return error
    return 1
}

function is_vscode_extension_installed() {
    local extension="$1"

    for installed_extension in "${installed_vscode_extensions[@]}"; do
        if [ "$installed_extension" == "$extension" ]; then
            log_debug "$extension is already installed, skipping."
            return 1
        fi
    done
    return 0
}


function install_vscode_extensions() {
    gum spin --title "Installing VSCode Extensions..." -- "${DOTFILES}/lib/install/vscode_extensions_standalone.sh"
    log_info "Installed VSCode Extensions."
}

function install_vscode_server_if_needed() {
    # Check if code-server is already installed
    if pkg_installed "code-server"; then
        log_debug "VSCode Server already installed"
        return
    fi

    log_info "Installing VSCode Server for virtualized environment..."

    # Install code-server using the official install script
    # This works across all platforms and is the recommended method
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL https://code-server.dev/install.sh | sh
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- https://code-server.dev/install.sh | sh
    else
        log_error "Neither curl nor wget available for installing code-server"
        return 1
    fi

    # Verify installation
    if pkg_installed "code-server"; then
        log_info "VSCode Server installed successfully"

        # Create a basic config if it doesn't exist
        local config_dir="$HOME/.config/code-server"
        local config_file="$config_dir/config.yaml"

        if [[ ! -f "$config_file" ]]; then
            mkdir -p "$config_dir"
            # TODO: Add Tailscale setup and verification before creating config
            # Once Tailscale is running, we can:
            # 1. Bind to Tailscale IP only for better security
            # 2. Remove password auth (auth: none) since Tailscale provides network-level security
            # 3. Use Tailscale hostname for easier connection
            cat > "$config_file" << EOF
bind-addr: 0.0.0.0:8080
auth: password
password: $(openssl rand -base64 32)
cert: false
EOF
            chmod 600 "$config_file"
            log_info "Created default code-server config at $config_file"
            log_info "Code server will listen on all interfaces at port 8080"
            log_info "Random password generated. Check $config_file for details."
            log_info "Connect from VSCode using: http://<container-ip>:8080"
        fi
    else
        log_error "VSCode Server installation failed"
        return 1
    fi
}

function install_vscode_if_needed() {
    # Check if we're in a virtualized environment (containers, VMs, etc.)
    if $is_virtualized; then
        log_info "Virtualized environment detected, installing VSCode Server instead of desktop VSCode"
        install_vscode_server_if_needed
        return
    fi

    # VSCode has different package names on different platforms
    # declare -A code_packages
    code_packages["arch"]="visual-studio-code-bin"
    if pkg_installed "code" code_packages; then
        return
    fi

    if $is_darwin; then
        brew install --cask visual-studio-code
        return
    fi

    # TODO: look into whether flatpak is a reasonable alternative for all
    # linux distros.
    if $is_debian_like; then
        echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
        sudo apt-get install wget gpg
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor >packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
        rm -f packages.microsoft.gpg
        sudo apt update
        sudo apt install apt-transport-https code
    elif $is_arch_like; then
        sudo "${package_manager}" -S code
    elif $is_fedora_like; then
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" |
            sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
        "${package_manager}" check-update
        sudo "${package_manager}" install code
    else
        log_error "Unknown distribution, how did this happen?"
    fi
}

if [ -z "$sourced_install_vscode" ]; then
    install_vscode_if_needed
    install_vscode_extensions
fi
