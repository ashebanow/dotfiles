#!/usr/bin/env bash

# Standalone script to install xcodes via homebrew
# This script uses the common homebrew utilities

set -euo pipefail

# Source the homebrew utilities  
source "${DOTFILES}/lib/common/homebrew_utils.sh"

# Install xcodes using homebrew environment
run_with_homebrew_env brew install xcodes