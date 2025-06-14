# this bash file is intended to be sourced as a library.
# It assumes you have already included the install_common.sh
# file.

# make sure we only source this once.
if [ -n $sourced_install_zed ]; then
  return;
fi
sourced_install_zed=true

if [ "$ID" == "darwin" ]; then
	brew install --cask zed
else
	# Use the per-user installer by default on linux systems.
	curl -f https://zed.dev/install.sh | sh
fi
