#!/usr/bin/env bash

# make sure we only source this once.
if is_sourced; then
  if [ -n $sourced_install_vscode ]; then
    return;
  fi
  sourced_install_vscode=true
fi

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

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

if ! is_sourced; then
  install_vscode_extensions
fi
