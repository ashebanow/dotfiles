# this bash file is intended to be sourced as a library.
# It assumes you have already included the install_common.sh
# file.

# make sure we only source this once.
if [ -n $sourced_install_bitwarden ]; then
  return;
fi
sourced_install_bitwarden=true
