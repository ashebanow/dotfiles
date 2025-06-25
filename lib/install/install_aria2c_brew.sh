#!/usr/bin/env bash

# Standalone script to install aria2c via homebrew  
# This script uses the common homebrew utilities

set -euo pipefail

# Source the homebrew utilities
source "${DOTFILES}/lib/common/homebrew_utils.sh"

# Install aria2 using homebrew environment
run_with_homebrew_env brew install aria2