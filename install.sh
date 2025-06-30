#!/bin/bash

# Dotfiles installation script with bitwarden session management
# Copied from: https://github.com/twpayne/chezmoi

set -e # -e: exit on error

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# Show help function
show_help() {
    cat << EOF
Dotfiles Installation Script

USAGE:
    $0 [OPTIONS]

DESCRIPTION:
    Installs and configures a complete development environment using chezmoi
    dotfiles management. This script will:

    • Install chezmoi if not present
    • Set up prerequisites (Homebrew, Node.js, development tools)
    • Install platform-specific packages (Arch, Flatpak, Homebrew)
    • Configure development applications (VS Code, Zed, Claude Code)
    • Set up Bitwarden integration for secrets management
    • Apply dotfiles configuration templates

OPTIONS:
    --debug           Enable debug mode with verbose output and bash tracing
    --user USERNAME   Set username for Bitwarden Apple ID lookup (default: ashebanow)
    --help            Show this help message and exit

EXAMPLES:
    $0                      # Normal installation (uses 'ashebanow' user)
    $0 --user john          # Installation using 'john_apple_id' Bitwarden entry
    $0 --debug              # Installation with debug output
    $0 --help               # Show this help

For more information, see: https://github.com/ashebanow/dotfiles
EOF
}

# Parse command line arguments
DEBUG_MODE=false
USER_NAME=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG_MODE=true
            shift
            ;;
        --user)
            if [[ -n "$2" && "$2" != --* ]]; then
                USER_NAME="$2"
                shift 2
            else
                log_error "Error: --user requires a username argument"
                log_error "Try '$0 --help' for more information."
                exit 1
            fi
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            log_error "Usage: $0 [--debug] [--user USERNAME] [--help]"
            log_error "Try '$0 --help' for more information."
            exit 1
            ;;
    esac
done

# Set debug options if requested
if [[ "$DEBUG_MODE" == "true" ]]; then
    log_debug "🐛 Debug mode enabled"
    export GUM_LOG_LEVEL=debug
    set -x  # Enable bash debug tracing
fi

# Set Apple ID username for Bitwarden lookup (with default)
export APPLE_ID_USER="${USER_NAME:-ashebanow}"

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
    log_error "To install chezmoi, you must have curl or wget installed."
    exit 1
  fi
else
  chezmoi=chezmoi
fi

# Initialize chezmoi without applying (to set up source directory)
log_info "Initializing chezmoi..."
"$chezmoi" init --source="$script_dir"

# Run install scripts to set up dependencies
export DOTFILES="$script_dir"
# Set flag to prevent recursive calls from run_onchange scripts
export DOTFILES_INSTALL_RUNNING=1
log_info "Running installation scripts..."
"$script_dir/lib/install/main.sh"

# Establish bitwarden session for template expansion
log_info "Setting up Bitwarden session for template expansion..."
if [ -x "$script_dir/home/private_dot_local/bin/executable_bw-session-manager" ]; then
  # Use the new session manager from source
  export BW_SESSION=$("$script_dir/home/private_dot_local/bin/executable_bw-session-manager" ensure)
elif [ -x "$script_dir/home/private_dot_local/bin/executable_bw-open" ]; then
  # Fallback to bw-open from source
  export BW_SESSION=$("$script_dir/home/private_dot_local/bin/executable_bw-open")
else
  log_error "Error: Bitwarden session tools not found. Cannot proceed with template expansion."
  log_error "Expected files:"
  log_error "  $script_dir/home/private_dot_local/bin/executable_bw-session-manager"
  log_error "  $script_dir/home/private_dot_local/bin/executable_bw-open"
  exit 1
fi

# Now apply all templates with bitwarden session available
log_info "Applying dotfiles configuration..."
"$chezmoi" apply
log_info "Applied dotfiles configuration..."

log_info "✅ Dotfiles installation complete!"
log_info ""
log_info "The bitwarden session service is now running and will manage"
log_info "persistent sessions automatically. Use 'bw-open' in new shells"
log_info "to get the session when you need bitwarden access."
