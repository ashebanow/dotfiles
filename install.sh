#!/bin/bash

# Dotfiles installation script with bitwarden session management
# Copied from: https://github.com/twpayne/chezmoi

set -e # -e: exit on error

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

# Install chezmoi if not available
if [ ! "$(command -v chezmoi)" ]; then
  bin_dir="$HOME/.local/bin"
  chezmoi="$bin_dir/chezmoi"
  if [ "$(command -v curl)" ]; then
    sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$bin_dir"
  elif [ "$(command -v wget)" ]; then
    sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$bin_dir"
  else
    echo "To install chezmoi, you must have curl or wget installed." >&2
    exit 1
  fi
else
  chezmoi=chezmoi
fi

# Initialize chezmoi without applying (to set up source directory)
echo "Initializing chezmoi..."
"$chezmoi" init --source="$script_dir"

# Run install scripts to set up dependencies
export DOTFILES="$script_dir"
echo "Running installation scripts..."
"$script_dir/bin/install_main.sh"

# Establish bitwarden session for template expansion
echo "Setting up Bitwarden session for template expansion..."
if [ -x "$script_dir/home/private_dot_local/bin/executable_bw-session-manager" ]; then
  # Use the new session manager from source
  export BW_SESSION=$("$script_dir/home/private_dot_local/bin/executable_bw-session-manager" ensure)
elif [ -x "$script_dir/home/private_dot_local/bin/executable_bw-open" ]; then
  # Fallback to bw-open from source
  export BW_SESSION=$("$script_dir/home/private_dot_local/bin/executable_bw-open")
else
  echo "Error: Bitwarden session tools not found. Cannot proceed with template expansion." >&2
  echo "Expected files:" >&2
  echo "  $script_dir/home/private_dot_local/bin/executable_bw-session-manager" >&2
  echo "  $script_dir/home/private_dot_local/bin/executable_bw-open" >&2
  exit 1
fi

# Now apply all templates with bitwarden session available
echo "Applying dotfiles configuration..."
"$chezmoi" apply

echo "✅ Dotfiles installation complete!"
echo ""
echo "The bitwarden session service is now running and will manage"
echo "persistent sessions automatically. Use 'bw-open' in new shells"
echo "to get the session when you need bitwarden access."
