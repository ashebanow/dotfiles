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
    local exit_code=0
    
    if command -v gum >/dev/null 2>&1; then
        # Temporarily disable debug output to avoid terminal interference
        local saved_log_level="${GUM_LOG_LEVEL:-info}"
        export GUM_LOG_LEVEL="error"
        
        if [[ "$saved_log_level" == "debug" ]]; then
            # For debug mode, show output but suppress our internal debug messages
            gum spin --spinner meter --title="$1" --show-output -- bash -c "$2"
            exit_code=$?
        else
            # Normal mode - no output shown
            gum spin --spinner meter --title="$1" -- bash -c "$2"
            exit_code=$?
        fi
        
        # Restore original log level
        export GUM_LOG_LEVEL="$saved_log_level"
        
        if [[ $exit_code -eq 0 ]]; then
            log_info "$3"
        else
            log_error "Command failed: $1"
        fi
    else
        # Fallback when gum is not available
        echo "⏳ $1"
        bash -c "$2"
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo "✅ $3"
        else
            echo "❌ Command failed: $1" >&2
        fi
    fi
    
    return $exit_code
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
