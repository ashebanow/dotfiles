# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

# make sure we only source this once.
if [ ! "${BASH_SOURCE[0]}" -ef "$0" ]; then
    if [ -n "$sourced_logging" ]; then
        return
    fi
    sourced_logging=true
fi

#######################################################################
# gum functions

# Parameters:()
# $1    pre_title
# $2    command
# $3    post_title      shown after gum returns
function show_spinner {
    gum spin --spinner meter --title "$1" -- "$2"
    log_info "$3"
}

#######################################################################
# logging functions - not to be used unless gum is installed already.
# Normally this is done by install-prereqisites.sh, which includes this
# file.

function log_debug {
    gum log --structured --level debug "$@"
}

function log_info {
    gum log --structured --level info "$@"
}

function log_warning {
    gum log --structured --level warning "$@"
}

function log_error {
    gum log --structured --level error "$@"
}
