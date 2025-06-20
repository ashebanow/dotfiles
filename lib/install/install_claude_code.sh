#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_claude_code" ] && [ "$sourced_install_claude_code" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_claude_code=true
fi

function install_claude_code_if_needed() {
    # TODO: implement
    true
}

if [ -z "$sourced_install_claude_code" ]; then
    install_claude_code_if_needed
fi
