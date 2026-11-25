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
    # Normalize trailing slashes (except a bare "/"): a trailing slash makes
    # the string compare unequal to the unslashed entry, so both land in PATH
    # and every lookup prints a doubled separator (e.g. bin//bat).
    case "$d" in
      */) d="${d%/}" ;;
    esac
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
add_to_path "/nix/var/nix/profiles/default/bin"
add_to_path "/run/current-system/sw/bin"
add_to_path "/etc/profiles/per-user/ashebanow/bin"
add_to_path "$HOME/.nix-profile/bin"

#############################################################################
# Shared user bins (existence-guarded no-ops on machines without them).
# ~/bin first (was bash-only — keeps bash's old priority order).

add_to_path "$HOME/bin"

# bun (standalone runtime; brew-specific paths live in devtools.sh)
export BUN_INSTALL="$HOME/.bun"
add_to_path "$BUN_INSTALL/bin"

# No ~/.claude/local here on purpose: it was Claude Code's old "local install"
# directory. Claude Code comes from nix-config now (lib/overlays/claude-code.nix
# pins it to Anthropic's release channel and shims `claude update`), and any
# binary left under ~/.claude/local would win this lookup and silently shadow
# the Nix build — exactly how a stray native install under ~/.local/bin ended
# up running a different version than the one the config declared. Don't
# re-add it; `just update-claude-code` in nix-config is the upgrade path.

add_to_path "$HOME/.cargo/bin"
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.npm-global/bin"
add_to_path "$HOME/.lmstudio/bin"
add_to_path "$HOME/.amp/bin"

# Added by LM Studio CLI tool (lms)
add_to_path "$HOME/.lmstudio/bin"

# On macOS the Rex app ships both halves of Rex — the server and the CLI — as
# one binary inside the app bundle, so there is nothing to install and nothing
# to keep in step with a Nix build. This puts that binary on PATH.
#
# The path names `Rex`, not `Rex Beta`: upstream renamed the app bundle very
# recently, and this line still carried the beta name, so it added a directory
# that did not exist and `rex` silently resolved to the Nix package instead.
# That is a live risk while Rex is prerelease — the bundle can move again — so
# this is the one line to check if the app's CLI ever stops being found.
#
# When Rex ships properly it should arrive in Homebrew and nixpkgs, at which
# point the app installs itself and this line goes away entirely.
#
# The bundle is "Rex Server.rex", which is what the app uses for the helper —
# not a typo for a .app suffix.
#
# TODO: do the equivalent for linux if needed once the linux app/server is available
# Quote, don't backslash-escape the spaces: paths.sh is shared with bash, and
# quoting is the form both shells read identically. (The escaped form happens to
# also work -- add_to_path's `eval echo` unescapes it and its export is quoted --
# so this is consistency, not a fix.)
add_to_path "/Applications/Rex.app/Contents/Helpers/Rex Server.rex/Contents/MacOS"

# NixOS: /etc/set-environment puts /run/wrappers/bin (the setuid sudo
# wrapper) on PATH, but the add_to_path calls above re-prepend
# nix/sw/bin/etc. after it, burying the wrapper below
# /run/current-system/sw/bin — whose store sudo binary has no setuid, so
# every `sudo` invocation fails. add_to_path is add-if-absent, so move the
# wrapper dir to the front explicitly. Existence-guarded: no-op on
# macOS/other platforms (BOX-126).
if [ -d /run/wrappers/bin ]; then
  PATH="$(printf '%s' "$PATH" | tr ':' '\n' | sed '\#^/run/wrappers/bin$#d' | paste -sd: -)"
  PATH="/run/wrappers/bin${PATH:+:$PATH}"
fi
