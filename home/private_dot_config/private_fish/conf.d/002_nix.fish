#fish_add_path -g "~/.nix-profile/bin"

set NIX_PROFILE_FILE_SUFFIX "etc/profile.d/nix-daemon.fish"
if test -f "/nix/var/nix/profiles/default/$NIX_PROFILE_FILE_SUFFIX"
  source "/nix/var/nix/profiles/default/$NIX_PROFILE_FILE_SUFFIX"
else if test -f "$HOME/.nix-profile/$NIX_PROFILE_FILE_SUFFIX"
  source "$HOME/.nix-profile/$NIX_PROFILE_FILE_SUFFIX"
end
