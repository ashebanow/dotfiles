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
    if command -v gum >/dev/null 2>&1; then
        if [[ "${GUM_LOG_LEVEL:-info}" == "debug" ]]; then
            gum spin --spinner meter --title "$1" --show-output -- "$2"
        else
            gum spin --spinner meter --title "$1" -- "$2"
        fi
        log_info "$3"
    else
        # Fallback when gum is not available
        echo "⏳ $1"
        "$2"
        echo "✅ $3"
    fi
}

#######################################################################
# logging functions with fallbacks for when gum is not available yet

function log_debug {
    if command -v gum >/dev/null 2>&1; then
        gum log --structured --level=debug "$@"
    elif [[ "${GUM_LOG_LEVEL:-info}" == "debug" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

function log_info {
    if command -v gum >/dev/null 2>&1; then
        gum log --structured --level=info "$@"
    else
        echo "ℹ️  $*"
    fi
}

function log_warning {
    if command -v gum >/dev/null 2>&1; then
        gum log --structured --level=warn "$@"
    else
        echo "⚠️  $*" >&2
    fi
}

function log_error {
    if command -v gum >/dev/null 2>&1; then
        gum log --structured --level=error "$@"
    else
        echo "❌ $*" >&2
    fi
}
