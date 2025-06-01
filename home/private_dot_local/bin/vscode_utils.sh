#!/bin/bash

# vscode_utils.sh - Utilities for working with VSCode

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