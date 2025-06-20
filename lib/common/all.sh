# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

# Abort if executed directly instead of sourced
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
    echo "Error: ${BASH_SOURCE[0]} is meant to be sourced, not executed directly." >&2
    echo "Usage: source \"${BASH_SOURCE[0]}\"" >&2
    exit 1
fi

# make sure we only source this once.
if [ -n "$sourced_common_all" ]; then
    return
fi
sourced_common_all=true

# for debugging, uncomment the following line and set the
# GUM_DEBUG_LEVEL to "debug".
set -x
# export GUM_LOG_LEVEL=info
export GUM_LOG_LEVEL=debug
# uncomment this to have everything fail fast, which can make debugging easier.
# But note that this will fail even working scripts in some cases.
# set -euo pipefail

# Source all common functionality
COMMON_DIR="${DOTFILES}/lib/common"
source "${COMMON_DIR}/system_environment.sh"
source "${COMMON_DIR}/logging.sh"
source "${COMMON_DIR}/packages.sh"
