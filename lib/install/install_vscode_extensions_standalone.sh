#!/usr/bin/env bash

# Standalone script to install VSCode extensions
# This script contains all necessary functions and logic

set -euo pipefail

# Source common functions for logging
source "${DOTFILES}/lib/common/all.sh"

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

    for binary_name in "${binary_names[@]}"; do
        if command -v "$binary_name" >/dev/null 2>&1; then
            echo "$binary_name"
            return 0
        fi
    done

    # If not found, return error
    return 1
}

is_vscode_extension_installed() {
    local extension="$1"

    for installed_extension in "${installed_vscode_extensions[@]}"; do
        if [ "$installed_extension" == "$extension" ]; then
            log_debug "$extension is already installed, skipping."
            return 1
        fi
    done
    return 0
}

# Main extension installation logic
main() {
    vscode_binary_path="$(find_vscode_binary)"
    if [ $? -ne 0 ] || [ -z "$vscode_binary_path" ]; then
        log_error "You must have the VSCode 'code' or equivalent binary in your PATH."
        exit 1
    fi

    declare -a installed_vscode_extensions
    readarray -t installed_vscode_extensions < <($vscode_binary_path --list-extensions)

    readarray -t vscode_extensions_list <"${DOTFILES}/VSExtensionsFile"
    for vscode_extension in "${vscode_extensions_list[@]}"; do
        if is_vscode_extension_installed "$vscode_extension"; then
            "$vscode_binary_path" --install-extension "$vscode_extension" --force
        fi
    done
}

# Run main function
main "$@"