# this bash file is intended to be sourced as a library.
# It assumes you have already included the install_common.sh
# file.

# make sure we only source this once.
if [ -n $sourced_install_arch ]; then
  return;
fi
sourced_install_arch=true

function update_arch_if_needed() {
  if ! is_arch_like; then
    return;
  fi

  yay -Syu
}

function install_arch_packages() {
  if ! is_arch_like; then
    return;
  fi

  readarray -t arch_package_list <"{{- .chezmoi.config.sourceDir -}}/Archfile"
  yay -S --needed --noconfirm --noprogressbar -q "${arch_package_list[@]}"
}
