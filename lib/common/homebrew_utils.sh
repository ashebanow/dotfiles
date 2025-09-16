# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

# make sure we only source this once.
if [ ! "${BASH_SOURCE[0]}" -ef "$0" ]; then
    if [ -n "${sourced_homebrew_utils:-}" ]; then
        return
    fi
    sourced_homebrew_utils=true

    # TODO: for debugging only, should be commented out once debugged.
    # export GUM_LOG_LEVEL="${GUM_LOG_LEVEL:-debug}"
    # set -x
fi

source "${DOTFILES}/lib/common/logging.sh"

#######################################################################
# Homebrew utility functions

# Find the homebrew binary in standard locations
# Returns the path to the brew binary, or exits with error if not found
function find_brew_binary() {
    local brew_locations=(
        "/opt/homebrew/bin/brew"
        "/usr/local/bin/brew"
        "/home/linuxbrew/.linuxbrew/bin/brew"
    )

    for brew_path in "${brew_locations[@]}"; do
        if [[ -x "$brew_path" ]]; then
            echo "$brew_path"
            return 0
        fi
    done

    # Check if brew is already in PATH (fallback)
    if command -v brew >/dev/null 2>&1; then
        command -v brew
        return 0
    fi

    return 1
}

# Set up homebrew environment using shellenv
# This function sets all necessary homebrew environment variables
function setup_homebrew_env() {
    local brew_binary
    brew_binary=$(find_brew_binary)

    if [[ $? -eq 0 && -n "$brew_binary" ]]; then
        eval "$("$brew_binary" shellenv)"
        return 0
    else
        echo "Error: Homebrew not found in standard locations" >&2
        return 1
    fi
}

# Run a command with proper homebrew environment setup
# Usage: run_with_homebrew_env command [args...]
function run_with_homebrew_env() {
    # Set up homebrew environment
    if ! setup_homebrew_env; then
        return 1
    fi

    log_debug "Running command: $*"

    # Execute the passed command with all arguments
    "$@"
}
