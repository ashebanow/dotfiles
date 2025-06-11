
# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

set -euo pipefail

# for debugging, uncomment the following line and set the
# GUM_DEBUG_LEVEL to "debug".
# set -x
export GUM_LOG_LEVEL=info

# platform identification
is_darwin=false
if [[ "$(uname -s)" == "Darwin" ]]; then
  is_darwin=true
  # Fake the crucial variables from /etc/os-release
  ID="darwin"
  PRODUCT_VERSION="$(sw_vers --productVersion)"
  BUILD_VERSION="$(sw_vers --buildVersion)"
else
  source /etc/os-release
fi

#######################################################################
# logging functions

function log_debug() {
  gum log --structured --level debug "$@"
}

function log_info() {
  gum log --structured --level info "$@"
}

function log_warning() {
  gum log --structured --level warning "$@"
}

function log_error() {
  gum log --structured --level error "$@"
}
