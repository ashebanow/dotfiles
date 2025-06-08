#!/bin/sh

set -e # -e: exit on error

# Default repo
repo_default="git@github.com:ashebanow/dotfiles.git"

print_help() {
  echo "Usage: $0 <destination> [--repo <git-repo>]"
  echo
  echo "This script installs chezmoi either locally or on a remote host."
  echo
  echo "Arguments:"
  echo "  destination  If 'local', the script will install chezmoi locally. If anything else, it will"
  echo "               assume it's an SSH host and will install chezmoi on the remote host."
  echo
  echo "Options:"
  echo "  --repo       Specify a different git repository to use. Default is \"$repo_default\"."
  echo "  -h, --help   Show this help message."
}

install_local() {
  repo="$1"
  if [ ! "$(command -v chezmoi)" ]; then
    bin_dir="$HOME/.local/bin"
    chezmoi="$bin_dir/chezmoi"
    if [ "$(command -v curl)" ]; then
      sh -c "$(curl -fsSL https://git.io/chezmoi)" -- -b "$bin_dir"
    elif [ "$(command -v wget)" ]; then
      sh -c "$(wget -qO- https://git.io/chezmoi)" -- -b "$bin_dir"
    else
      echo "To install chezmoi, you must have curl or wget installed." >&2
      exit 1
    fi
  else
    chezmoi=chezmoi
  fi

  # exec: replace current process with chezmoi init
  exec "$chezmoi" init "$repo"
}

install_remote() {
  repo="$1"
  remote_host="$2"
  script_name="$(basename "$0")"
  scp "$0" "$remote_host:/tmp/$script_name"
  ssh -t "$remote_host" "chmod +x /tmp/$script_name; /tmp/$script_name local --repo $repo"
}

# Parse command-line options
repo="$repo_default"
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      shift
      repo="$1"
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      # If it's neither --repo nor -h/--help, it must be the destination
      destination="$1"
      ;;
  esac
  shift
done

# If no destination was provided, print the help message
if [ -z "$destination" ]; then
  print_help
  exit 1
fi

if [ "$destination" = "local" ]; then
  install_local "$repo"
else
  install_remote "$repo" "$destination"
fi
