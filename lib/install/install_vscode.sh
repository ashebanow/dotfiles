#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/install_common.sh"

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

	readarray -t vscode_extensions_list <"{{- .chezmoi.config.sourceDir -}}/VSExtensionsFile"
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
