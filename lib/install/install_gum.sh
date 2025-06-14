# this bash file is intended to be sourced as a library.
# It assumes you have already included the install_common.sh
# file.

# make sure we only source this once.
if [ -n $sourced_install_gum ]; then
  return;
fi
sourced_install_gum=true

source "${DOTFILES}/lib/install/install_homebrew.sh"

function install_gum_if_needed() {
  if ! command -v brew; then
    log_info "homebrew not installed in install_gum.sh"
    install_homebrew_if_needed
  fi
  if command -v gum; then
    return;
  fi
  brew install gum
}
