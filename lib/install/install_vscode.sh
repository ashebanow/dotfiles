#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

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

function install_vscode_extensions_internal() {
	vscode_binary_path="$(find_vscode_binary)"
	if [ $? -ne 0 ] || [ -z "$vscode_binary_path" ]; then
		log_error "You must have the VSCode 'code' or equivalent binary in your PATH."
		exit 1
	fi

	declare -a installed_vscode_extensions
	readarray -t installed_vscode_extensions < <($vscode_binary_path --list-extensions)

	readarray -t vscode_extensions_list <"{{- .chezmoi.config.sourceDir -}}/VSExtensionsFile"
	for vscode_extension in "${vscode_extensions_list[@]}"; do
		if is_vscode_extension_installed "$vscode_extension"; then
			"$vscode_binary_path" --install-extension "$vscode_extension" --force
		fi
	done
}

function install_vscode_extensions() {
	gum spin --title "Installing VSCode Extensions..." -- install_vscode_extensions_internal
	log_info "Installed VSCode Extensions."
}

function install_vscode_if_needed() {
	if command -v code &> /dev/null; then
	    return
	fi

	if is_darwin; then
	    log_error "VSCode installation on Mac not yet supported."
		log_error "Please install VSCode manually, then rerun the script."
		exit 1
	fi

	// TODO: look into whether flatpak is a reasonable alternative for all
	// linux distros.
    if is_debian_like; then
        echo "code code/add-microsoft-repo boolean true" | sudo debconf-set-selections
        sudo apt-get install wget gpg
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
        sudo install -D -o root -g root -m 644 packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
        echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" |sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
        rm -f packages.microsoft.gpg
        sudo apt update
        sudo apt install apt-transport-https code
    elif is_arch_like; then
        sudo "${package_manager}" -S code
    elif is_fedora_like; then
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
            | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
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
