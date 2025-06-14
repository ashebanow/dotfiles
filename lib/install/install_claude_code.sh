# this bash file is intended to be sourced as a library.
# It assumes you have already included the install_common.sh
# file.

# make sure we only source this once.
if [ -n $sourced_install_claude_code ]; then
  return;
fi
sourced_install_claude_code=true

# TODO: make sure node and npm are installed and up to date,
# then use npm to install claude code
