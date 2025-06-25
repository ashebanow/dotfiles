#!/usr/bin/env bash

# Standalone script to run commands with homebrew environment
# Usage: run_with_homebrew_env.sh command [args...]

set -eo pipefail

# Source the homebrew utilities
source "${DOTFILES}/lib/common/homebrew_utils.sh"

# Run the command with homebrew environment
run_with_homebrew_env "$@"