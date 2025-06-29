#!/usr/bin/env bash

# Standalone script to install VSCode extensions
# This script contains all necessary functions and logic

set -eo pipefail

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
            return 0
        fi
    done
    return 1
}

# Main extension installation logic
main() {
    vscode_binary_path="$(find_vscode_binary)"
    if [ $? -ne 0 ] || [ -z "$vscode_binary_path" ]; then
        log_error "You must have the VSCode 'code' or equivalent binary in your PATH."
        exit 1
    fi

    # Get installed extensions (bash 3.2 compatible)
    declare -a installed_vscode_extensions
    while IFS= read -r extension; do
        installed_vscode_extensions+=("$extension")
    done < <("$vscode_binary_path" --list-extensions 2>/dev/null || true)

    # Read extensions to install (bash 3.2 compatible)
    declare -a vscode_extensions_list
    while IFS= read -r extension; do
        [[ -n "$extension" ]] && vscode_extensions_list+=("$extension")
    done < "${DOTFILES}/packages/VSExtensionsFile"
    for vscode_extension in "${vscode_extensions_list[@]}"; do
        if ! is_vscode_extension_installed "$vscode_extension"; then
            log_info "Installing VSCode extension: $vscode_extension"
            "$vscode_binary_path" --install-extension "$vscode_extension" --force >/dev/null 2>&1
        fi
    done
}

# Run main function
main "$@"
