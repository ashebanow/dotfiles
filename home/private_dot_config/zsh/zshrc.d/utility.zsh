# -----------------------------------------------------
# Utility functions
# -----------------------------------------------------

# do sudo, or sudo the last command if no argument given
s() {
  if [[ $# == 0 ]]; then
    sudo $(fc -ln -1)
  else
    sudo "$@"
  fi
}

# Archive extraction helper
source "$HOME/.local/bin/extract"
