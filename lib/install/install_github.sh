# this bash file is intended to be sourced as a library.
# It assumes you have already included the install_common.sh
# file.

# make sure we only source this once.
if [ -n $sourced_install_github ]; then
  return;
fi
sourced_install_github=true

# TODO: install github CLI (gh), auth, and add the copilot extension.
# going to be tricky to do the auth without templating.
