#!/usr/bin/env bash

# setup common to all install scripts
source "${DOTFILES}/lib/common/all.sh"

# make sure we only source this once.
if [[ ! "${BASH_SOURCE[0]}" -ef "$0" ]]; then
    if [ -n "$sourced_install_arch" ] && [ "$sourced_install_arch" = "true" ]; then
        log_debug "$0 has already been sourced, returning early"
        return
    fi
    sourced_install_arch=true
fi

function install_yay_if_needed() {
  sudo pacman -S --needed --noconfirm --noprogressbar git base-devel

  mkdir -p ~/Development/linux
  pushd ~/Development/linux
  git clone https://aur.archlinux.org/yay-bin.git
  cd yay-bin
  makepkg -si
  popd
}

function update_arch_if_needed() {
  if ! is_arch_like; then
    return;
  fi

  # Install yay if not available
  if ! command -v yay >/dev/null 2>&1; then
    install_yay_if_needed
  fi

  # Verify yay is now available before using it
  if ! command -v yay >/dev/null 2>&1; then
    log_error "yay installation failed or not in PATH"
    return 1
  fi

  yay -Syu
}

function install_arch_packages() {
  if ! is_arch_like; then
    return;
  fi

  # Ensure virtual environment is available (required for proper dependencies)
  if [[ ! -f "${DOTFILES}/.venv/bin/python3" ]]; then
    log_error "Python virtual environment not found at ${DOTFILES}/.venv/bin/python3"
    log_error "Please run 'just setup-python' from ${DOTFILES} first"
    return 1
  fi
  local PYTHON_CMD="${DOTFILES}/.venv/bin/python3"

  # Try to generate package lists from TOML first
  if [[ -f "${DOTFILES}/packages/package_mappings.toml" ]] && [[ -f "${DOTFILES}/bin/package_generators.py" ]]; then
    log_info "Generating Arch package list from TOML using ${PYTHON_CMD}..."
    if "${PYTHON_CMD}" "${DOTFILES}/bin/package_generators.py" \
        --toml "${DOTFILES}/packages/package_mappings.toml" \
        --output-dir "${DOTFILES}/packages" > "${DOTFILES}/packages/.package_generation.log" 2>&1; then
      log_info "✓ Generated Arch package list from TOML"
    else
      log_warn "Failed to generate from TOML, using existing Archfile"
    fi
  fi

  # Use DOTFILES environment variable instead of chezmoi template
  local archfile="${DOTFILES}/packages/Archfile"
  if [[ ! -f "$archfile" ]]; then
    log_error "Archfile not found at: $archfile"
    return 1
  fi

  # Ensure yay is available before using it
  if ! command -v yay >/dev/null 2>&1; then
    log_error "yay not found, cannot install Arch packages"
    return 1
  fi

  readarray -t arch_package_list <"$archfile"
  if [[ ${#arch_package_list[@]} -gt 0 ]]; then
    yay -S --needed --noconfirm --noprogressbar -q "${arch_package_list[@]}"
  else
    log_info "No Arch packages to install"
  fi
}

if [ -z "$sourced_install_arch" ]; then
    update_arch_if_needed
    install_arch_packages
fi
