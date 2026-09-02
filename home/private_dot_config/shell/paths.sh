# ~/.config/shell/paths.sh — PATH machinery (zsh and bash, POSIX)
# Sourced by .zshenv (after $ZDOTDIR/paths.zsh) and by .bashrc.
# add_to_path is defined here only if paths.zsh hasn't already: zsh gets the
# replay-recording version (macOS path_helper replay), bash gets this POSIX
# one. Feature probe, not a shell branch. All adds are existence-guarded, so
# a machine without a given tool simply skips it.

#############################################################################
# add_to_path — define only if paths.zsh hasn't already (zsh gets the
# replay-recording version; bash gets this POSIX one). Feature probe, not a
# shell branch.

if ! command -v add_to_path >/dev/null 2>&1; then
  add_to_path() {
    local target="" d
    for arg in "$@"; do case "$arg" in -d|--debug) ;; *) target="$arg";; esac; done
    [ -n "$target" ] || { echo "Usage: add_to_path [-d|--debug] <dir>" >&2; return 1; }
    d=$(eval echo "$target")
    [ -d "$d" ] || return 1
    case ":$PATH:" in *":$d:"*) return 0 ;; esac
    export PATH="$d:$PATH"
  }
fi

#############################################################################
# INITIALIZE NIX

NIX_PROFILE_FILE_SUFFIX="etc/profile.d/nix-daemon.sh"
if [ -f "/nix/var/nix/profiles/default/${NIX_PROFILE_FILE_SUFFIX}" ]; then
    source "/nix/var/nix/profiles/default/${NIX_PROFILE_FILE_SUFFIX}"
elif [ -f "$HOME/.nix-profile/${NIX_PROFILE_FILE_SUFFIX}" ]; then
    source "$HOME/.nix-profile/${NIX_PROFILE_FILE_SUFFIX}"
fi

# nix-daemon.sh already prepended these; record them for the .zprofile
# replay (nix stays ahead of Homebrew, matching the init order above)
add_to_path "~/Applications/Home\ Manager\ Apps/"
add_to_path "/nix/var/nix/profiles/default/bin"
add_to_path "/run/current-system/sw/bin/"
add_to_path "/etc/profiles/per-user/ashebanow/bin/"
add_to_path "$HOME/.nix-profile/bin"

#############################################################################
# Shared user bins (existence-guarded no-ops on machines without them).
# ~/bin first (was bash-only — keeps bash's old priority order).

add_to_path "$HOME/bin"

# bun (standalone runtime; brew-specific paths live in devtools.sh)
export BUN_INSTALL="$HOME/.bun"
add_to_path "$BUN_INSTALL/bin"

add_to_path "$HOME/.claude/local"
add_to_path "$HOME/.cargo/bin"
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.npm-global/bin"
add_to_path "$HOME/.lmstudio/bin"
add_to_path "$HOME/.amp/bin"

# Added by LM Studio CLI tool (lms)
add_to_path "$HOME/.lmstudio/bin"
