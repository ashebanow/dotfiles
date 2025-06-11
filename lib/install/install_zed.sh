#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/install_common.sh"

if [ "$ID" == "darwin" ]; then
  brew install --cask zed
else
  # Use the per-user installer by default on linux systems.
  curl -f https://zed.dev/install.sh | sh
fi
