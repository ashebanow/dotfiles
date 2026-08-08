#!/usr/bin/env bash

# setup common to all install scripts, but note that gum-dependent
# functions in this file won't work until gum gets installed, and
# thus should be avoided here.
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "${sourced_install_prerequisites:-}" ] && [ "$sourced_install_prerequisites" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_prerequisites=true
fi

#--------------------------------------------------------------------
# NOTES ON PLATFORM COVERAGE
#--------------------------------------------------------------------
#
# On the nix-managed hosts — macOS (nix-darwin + home-manager) and
# servers (NixOS) — every CLI tool this script used to install (node,
# gum, jq, bitwarden-cli, aria2, xcodes, tailscale, ...) now comes
# from the nix flake in the lumquat nix-config (modules/features/
# cli-*.nix, access.nix). Homebrew on macOS is limited to the casks
# declared in homebrew.casks, and nix-darwin's
# homebrew.onActivation.cleanup = "uninstall" removes anything not
# declared — so brew-installing these from here would just get
# uninstalled at the next darwin-rebuild switch.
#
# Consequently, on macOS this script only handles what nix doesn't:
# Xcode + Command Line Tools. The install functions below skip macOS
# (nix owns those tools) and only fall back to distro package
# managers (apt/pacman/dnf) on non-nix Linux.

#--------------------------------------------------------------------
# CHECK FOR REQUIRED TOOLS
#--------------------------------------------------------------------

need_flatpak=false
need_node=false
need_gum=false
need_bitwarden=false
need_keyring_tools=false
need_tailscale=false
need_jq=false
need_xcode=false

function checkNeededPrerequisites() {
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
    declare -a bw_packages=(
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
        declare -a secret_tool_packages=(
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

    # Check for Tailscale (Linux only — macOS uses the official .pkg
    # installer, NixOS hosts get it from services.tailscale)
    if ! $is_darwin && ! pkg_installed "tailscale"; then
        need_tailscale=true
    fi

    # Check for XCode (macOS only)
    if $is_darwin; then
        if ! is_xcode_command_line_tools_installed || ! is_xcode_app_installed; then
            need_xcode=true
        fi
    fi
}

#--------------------------------------------------------------------
# INSTALL NODE & NPM
#--------------------------------------------------------------------

# node/npm on macOS come from nix (cli-build-essentials.nix). This
# only installs on non-nix Linux distros.
function install_node_if_needed {
    if ! $need_node; then
        return
    fi

    if $is_darwin; then
        log_warning "node/npm not found on macOS — run the nix setup (darwin-rebuild switch) first; nix provides nodejs via home-manager (cli-build-essentials.nix)."
        return
    fi

    log_info "Installing Node.js and npm..."

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
        log_error "Unsupported OS for Node.js installation."
        exit 1
    fi
}

#--------------------------------------------------------------------
# INSTALL FLATPAK RUNTIME
#--------------------------------------------------------------------

# Flatpak runtime installation functions (Linux only — macOS returns early)
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

# bw on macOS comes from nix (cli-security-tools.nix) and the desktop
# app from the flake's homebrew.casks — nothing is installed from
# here on macOS. The functions below only serve non-nix Linux.

function arch_install_bitwarden_cli {
    # Make sure yay is installed
    if ! command -v yay >/dev/null 2>&1; then
        log_info "Installing yay..."
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
    declare -a bw_packages=(
        ["darwin"]="bitwarden-cli"
        ["arch"]="bitwarden-cli"
        ["fedora"]="bitwarden-cli"
    )
    if pkg_installed "bw" bw_packages; then
        return
    fi

    if is_arch_like; then
        arch_install_bitwarden_cli
    else
        pkg_install "bw" bw_packages
    fi
}

#--------------------------------------------------------------------
# INSTALL BITWARDEN DESKTOP
#--------------------------------------------------------------------

# Bitwarden Desktop installation functions (Linux only)
function arch_install_bitwarden_desktop {
    # Make sure yay is installed
    if ! command -v yay >/dev/null 2>&1; then
        log_info "Installing yay..."
        sudo pacman -Sq --needed --noconfirm git base-devel >/dev/null 2>&1
        pushd /tmp || exit 1
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
        log_debug "Bitwarden desktop is a declared cask in the nix flake — skipping"
        return
    fi

    if is_arch_like; then
        arch_install_bitwarden_desktop
    elif is_debian_like || is_fedora_like; then
        linux_native_install_bitwarden_desktop
    else
        log_error "Unsupported OS for Bitwarden desktop installation."
        exit 1
    fi
}

function install_bitwarden_if_needed {
    if ! $need_bitwarden; then
        return
    fi

    if $is_darwin; then
        log_warning "bw not found on macOS — run the nix setup (darwin-rebuild switch) first; nix provides bitwarden-cli via home-manager (cli-security-tools.nix)."
        return
    fi

    install_bitwarden_desktop_if_needed
    install_bitwarden_cli_if_needed

    log_warning "Be sure to setup your account(s) and vault(s) in bitwarden."
    log_warning "To do so, run 'bw login' in your terminal to login. Once the "
    log_warning "dots are installed, you will be asked to login automatically"
    log_warning "if needed."
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
    declare -a secret_tool_packages=(
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

# gum on macOS comes from nix (cli-productivity-tools.nix).
function install_gum_if_needed() {
    if ! $need_gum; then
        return
    fi

    if $is_darwin; then
        log_warning "gum not found on macOS — run the nix setup (darwin-rebuild switch) first; nix provides gum via home-manager (cli-productivity-tools.nix)."
        return
    fi

    pkg_install "gum"
}

#--------------------------------------------------------------------
# INSTALL JQ
#--------------------------------------------------------------------

# jq on macOS comes from nix (cli-productivity-tools.nix).
function install_jq_if_needed() {
    if ! $need_jq; then
        return
    fi

    if $is_darwin; then
        log_warning "jq not found on macOS — run the nix setup (darwin-rebuild switch) first; nix provides jq via home-manager (cli-productivity-tools.nix)."
        return
    fi

    pkg_install "jq"
}

#--------------------------------------------------------------------
# INSTALL XCODE AND COMMAND LINE TOOLS
#--------------------------------------------------------------------

# xcodes and aria2c are nix-provided on macOS (cli-mac-only-tools.nix,
# cli-network-tools.nix) and are expected to be on PATH; this section
# only installs what nix can't: the Command Line Tools and the full
# Xcode.app (via xcodes).

function is_xcode_command_line_tools_installed() {
    if ! $is_darwin; then
        return 0  # Always true on non-Mac platforms
    fi

    # Check if xcode-select can find the developer directory
    local dev_dir
    dev_dir=$(xcode-select -p 2>/dev/null)

    # Verify the directory exists and contains essential tools
    if [[ -n "$dev_dir" ]] && [[ -d "$dev_dir" ]] && [[ -f "$dev_dir/usr/bin/git" ]]; then
        log_debug "XCode Command Line Tools found at: $dev_dir"
        return 0
    else
        log_debug "XCode Command Line Tools not found or incomplete"
        return 1
    fi
}

function install_xcode_command_line_tools() {
    if ! $is_darwin; then
        return
    fi

    log_info "Installing XCode Command Line Tools..."

    # Trigger the installation dialog
    show_spinner "Installing XCode Command Line Tools" \
        "xcode-select --install" \
        "XCode Command Line Tools installation initiated"

    # Wait for installation to complete
    log_info "Waiting for Command Line Tools installation to complete..."
    log_warning "Please follow the on-screen prompts to complete the installation"

    # Poll until installation is complete
    local max_attempts=60  # Wait up to 30 minutes (60 * 30s)
    local attempt=0

    while ! is_xcode_command_line_tools_installed && [[ $attempt -lt $max_attempts ]]; do
        sleep 30
        attempt=$((attempt + 1))
        log_debug "Waiting for Command Line Tools installation... (attempt $attempt/$max_attempts)"
    done

    if is_xcode_command_line_tools_installed; then
        log_info "XCode Command Line Tools installation completed successfully"
    else
        log_error "XCode Command Line Tools installation timed out or failed"
        log_error "Please complete the installation manually and re-run this script"
        return 1
    fi
}

function is_xcode_app_installed() {
    if ! $is_darwin; then
        return 0  # Always true on non-Mac platforms
    fi

    if [[ -d "/Applications/Xcode.app" ]] && [[ -x "/Applications/Xcode.app/Contents/MacOS/Xcode" ]]; then
        log_debug "Full Xcode.app found at /Applications/Xcode.app"
        return 0
    else
        log_debug "Full Xcode.app not found"
        return 1
    fi
}

function setup_xcodes_credentials() {
    if ! $is_darwin; then
        return 0
    fi

    # Skip if already set
    if [[ -n "${XCODES_USERNAME:-}" ]] && [[ -n "${XCODES_PASSWORD:-}" ]]; then
        log_debug "XCODES credentials already set"
        return 0
    fi

    if ! command -v bw >/dev/null 2>&1; then
        log_error "Bitwarden CLI not available, cannot retrieve Apple ID credentials"
        return 1
    fi

    log_debug "Retrieving Apple ID credentials from Bitwarden..."

    # Create secure temporary files
    local temp_username_file
    local temp_password_file
    temp_username_file=$(mktemp)
    temp_password_file=$(mktemp)

    # Set secure permissions
    chmod 600 "$temp_username_file" "$temp_password_file"

    # Get the Apple ID username from environment variable (defaults to 'ashebanow')
    local apple_id_user="${APPLE_ID_USER:-ashebanow}"
    local bitwarden_key="${apple_id_user}_apple_id"

    log_debug "Using Bitwarden key: $bitwarden_key"

    # Retrieve credentials from Bitwarden
    if ! bw get username "$bitwarden_key" > "$temp_username_file" 2>/dev/null; then
        log_error "Failed to retrieve Apple ID username from Bitwarden (key: $bitwarden_key)"
        rm -f "$temp_username_file" "$temp_password_file"
        return 1
    fi

    if ! bw get password "$bitwarden_key" > "$temp_password_file" 2>/dev/null; then
        log_error "Failed to retrieve Apple ID password from Bitwarden (key: $bitwarden_key)"
        rm -f "$temp_username_file" "$temp_password_file"
        return 1
    fi

    # Set environment variables securely (avoiding shell history)
    export XCODES_USERNAME=$(cat "$temp_username_file")
    export XCODES_PASSWORD=$(cat "$temp_password_file")

    # Clean up temporary files
    rm -f "$temp_username_file" "$temp_password_file"

    if [[ -n "${XCODES_USERNAME:-}" ]] && [[ -n "${XCODES_PASSWORD:-}" ]]; then
        log_debug "Apple ID credentials set successfully"
        return 0
    else
        log_error "Failed to set Apple ID credentials"
        return 1
    fi
}

function is_authenticated_with_apple_developer() {
    if ! $is_darwin; then
        return 0  # Always true on non-Mac platforms
    fi

    if ! command -v xcodes >/dev/null 2>&1; then
        log_debug "xcodes not installed, cannot check Apple Developer authentication"
        return 1
    fi

    # Setup credentials from Bitwarden if needed
    setup_xcodes_credentials

    # Check if authenticated by trying to list available Xcode versions
    # xcodes will use environment variables for authentication if available
    if xcodes list >/dev/null 2>&1; then
        log_debug "Authenticated with Apple Developer"
        return 0
    else
        log_debug "Not authenticated with Apple Developer"
        return 1
    fi
}

function install_xcode_app() {
    if ! $is_darwin; then
        return
    fi

    # xcodes is nix-provided and should already be on PATH at this point
    if ! command -v xcodes >/dev/null 2>&1; then
        log_error "xcodes command line tool not found. Please ensure the nix setup has been run (nix provides xcodes via cli-mac-only-tools.nix)."
        return 1
    fi

    # Setup Apple ID credentials from Bitwarden
    if ! setup_xcodes_credentials; then
        log_error "Failed to setup Apple ID credentials"
        return 1
    fi

    # Attempt automatic signin if not already authenticated
    if ! is_authenticated_with_apple_developer; then
        log_info "Signing into Apple Developer account..."

        # xcodes signin will use XCODES_USERNAME and XCODES_PASSWORD environment variables
        if ! show_spinner "Signing into Apple Developer account" \
            "xcodes signin" \
            "Apple Developer authentication completed"; then
            local apple_id_user="${APPLE_ID_USER:-ashebanow}"
            local bitwarden_key="${apple_id_user}_apple_id"
            log_error "Failed to sign into Apple Developer account"
            log_error "Please check your Apple ID credentials in Bitwarden (key: $bitwarden_key)"
            return 1
        fi

        # Verify authentication worked
        if ! is_authenticated_with_apple_developer; then
            log_error "Authentication verification failed"
            return 1
        fi
    else
        log_debug "Already authenticated with Apple Developer"
    fi

    # Install Xcode using xcodes (aria2c from nix speeds up the download)
    show_spinner "Installing Xcode (this may take a while)" \
        "xcodes install --latest XCode --experimental-unxip" \
        "Installed XCode."

    # Verify installation
    if is_xcode_app_installed; then
        log_info "Xcode installation completed successfully"

        # Set Xcode as the active developer directory
        log_info "Setting Xcode as active developer directory..."
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

        # Accept Xcode license if needed
        log_info "Accepting Xcode license agreement..."
        sudo xcodebuild -license accept 2>/dev/null || {
            log_warning "Please accept the Xcode license agreement manually:"
            log_warning "Run: sudo xcodebuild -license"
        }
    else
        log_error "Xcode installation verification failed"
        return 1
    fi
}

function mac_install_cmd_line_tools_if_needed() {
    if ! $is_darwin; then
        log_debug "Not on macOS, skipping XCode Command Line Tools installation"
        return
    fi

    if ! is_xcode_command_line_tools_installed; then
        log_info "XCode Command Line Tools not found, installing..."
        install_xcode_command_line_tools
    else
        log_debug "XCode Command Line Tools already installed"
    fi
}

function install_simulator_runtime() {
    local platform_name="$1"      # Official platform name for grep (e.g., "macOS", "iOS", "watchOS")
    local display_name="$2"       # Human readable name for messages (e.g., "macOS", "iOS", "watchOS")

    # Find latest stable runtime for the platform
    local latest_runtime
    latest_runtime=$(xcodes runtimes | grep "$platform_name" | grep -v "Beta" | grep -v "^--" | tail -1)
    log_debug "Latest runtime: $latest_runtime"

    if [[ -n "$latest_runtime" ]]; then
        log_info "Installing $display_name runtime: $latest_runtime"
        show_spinner "Installing $latest_runtime runtime" \
            "xcodes runtimes install \"$latest_runtime\"" \
            "$display_name runtime installation completed"
    else
        log_debug "No $display_name runtimes available or already installed"
    fi
}

function install_xcode_simulators() {
    if ! $is_darwin; then
        return
    fi

    if ! command -v xcodes >/dev/null 2>&1; then
        log_error "xcodes not installed, cannot install simulators"
        return 1
    fi

    log_info "Installing macOS, iOS, and watchOS simulators..."

    # Install in priority order: most immediately useful first
    install_simulator_runtime "macOS" "macOS"
    install_simulator_runtime "iOS" "iOS"
    install_simulator_runtime "watchOS" "watchOS"
}

function mac_install_xcode_if_needed() {
    if ! $is_darwin; then
        log_debug "Not on macOS, skipping full XCode installation"
        return
    fi

    if ! is_xcode_app_installed; then
        log_info "Full Xcode not found, installing..."
        install_xcode_app

        # After installing Xcode, install simulators
        log_info "Installing additional simulators and runtimes..."
        install_xcode_simulators
    else
        log_debug "Full Xcode already installed"

        # Check if we should install additional simulators
        log_info "Checking for additional simulators..."
        install_xcode_simulators
    fi
}

#--------------------------------------------------------------------
# INSTALL TAILSCALE
#--------------------------------------------------------------------

# Tailscale on macOS uses the official .pkg installer (the flake's
# cli-network-tools.nix deliberately avoids nix/homebrew builds — the
# MAS build is sandboxed and the nixpkgs build won't start on macOS),
# and NixOS hosts get it from services.tailscale (access.nix). This
# only installs on non-nix Linux distros.
function install_tailscale_if_needed() {
    if ! $need_tailscale; then
        return
    fi

    log_info "Installing Tailscale..."

    # Define Tailscale repository configurations
    declare -a tailscale_repos=(
        ["debian"]='{
            "base_url": "https://pkgs.tailscale.com/stable/debian",
            "version_name": "auto",
            "key_url": "https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg"
        }'
        ["fedora"]="https://pkgs.tailscale.com/stable/fedora/tailscale.repo"
    )

    # Define post-install hooks
    declare -a tailscale_post=(
        ["arch"]="sudo systemctl enable --now tailscaled"
        ["fedora"]="sudo systemctl enable --now tailscaled"
    )

    # Install using the unified pkg_install function
    pkg_install "tailscale" "" tailscale_repos "" tailscale_post

    log_info "Tailscale installed successfully"
}

#--------------------------------------------------------------------
# CORE LOGIC
#--------------------------------------------------------------------

function install_prerequisites() {
    checkNeededPrerequisites
    # Install XCode Command Line Tools first (required for nix on macOS)
    mac_install_cmd_line_tools_if_needed
    install_flatpak_if_needed
    install_bitwarden_if_needed
    install_node_if_needed
    install_keyring_tools_if_needed
    install_jq_if_needed
    install_gum_if_needed
    install_tailscale_if_needed
    # Install Xcode at the end (requires xcodes from nix and Bitwarden
    # for Apple ID authentication)
    mac_install_xcode_if_needed
}

if [ -z "$sourced_install_prerequisites" ]; then
    install_prerequisites
fi
