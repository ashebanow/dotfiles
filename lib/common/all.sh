# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

# make sure we only source this once.
if [ ! "${BASH_SOURCE[0]}" -ef "$0" ]; then
    if [ -n "$sourced_common_all" ]; then
        return
    fi
    sourced_common_all=true
fi

# Source all common functionality
COMMON_DIR="${DOTFILES}/lib/common"
source "${COMMON_DIR}/system_environment.sh"
source "${COMMON_DIR}/logging.sh"