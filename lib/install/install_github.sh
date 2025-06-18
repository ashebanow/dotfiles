#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/install/install_common.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_github" ] && [ "$sourced_install_github" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_github=true
fi

function install_github_cli() {
  # TODO: fix this setup so that it does `gh auth login` and
  # `gh auth status -a`.

  # if command -v gh; then
  # log_info "Installing GitHub CLI Copilot extensions..."
  # if $(gh extension list | grep -q gh-copilot); then
  # gh extension upgrade github/gh-copilot
  # else
  # gh extension install github/gh-copilot
  # fi
  # fi
}

if [ -z "$sourced_install_github" ]; then
    install_github_cli
fi
