# NOTE: this file is only meant to be sourced by other scripts.
# It is not meant to be executed directly.

set -euo pipefail

# for debugging, uncomment the following line and set the
# GUM_DEBUG_LEVEL to "debug".
# set -x
export GUM_LOG_LEVEL=info

# platform identification
is_darwin=false
is_arch_like=false
is_debian_like=false
is_fedora_like=false
if [[ "$(uname -s)" == "Darwin" ]]; then
  is_darwin=true
  # Fake the crucial variables from /etc/os-release
  ID="darwin"
  PRODUCT_VERSION="$(sw_vers --productVersion)"
  BUILD_VERSION="$(sw_vers --buildVersion)"
else
  source /etc/os-release

  if [[ $ID == "arch" || (-n $ID_LIKE && $ID_LIKE == "arch") ]]; then
    is_arch_like=true
  fi

  if [[ $ID == "debian" || (-n $ID_LIKE && $ID_LIKE == "debian") ]]; then
    is_debian_like=true
  fi

  if [[ $ID == "fedora" || (-n $ID_LIKE && $ID_LIKE == "fedora") ]]; then
    is_fedora_like=true
  fi
fi

function fn_exists() { declare -F "$1" > /dev/null; }

#######################################################################
# gum functions

# Parameters:
# $1    pre_title
# $2    command
# $3    post_title      shown after gum returns
function show_spinner() {
	gum spin --spinner meter --title "$1" -- "$2"
	log_info "$3"
}

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
