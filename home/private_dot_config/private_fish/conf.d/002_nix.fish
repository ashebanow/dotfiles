#fish_add_path -g "~/.nix-profile/bin"

set NIX_PROFILE_FILE "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish"
if test -f "$NIX_PROFILE_FILE"
  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.fish
end
