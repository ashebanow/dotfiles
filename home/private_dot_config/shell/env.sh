# ~/.config/shell/env.sh — shared environment for zsh and bash (POSIX-ish)
# Sourced by .zshenv (every zsh, after paths.zsh) and by .bashrc (interactive
# bash). Idempotent via the _ENV_SH_SOURCED guard (same pattern paths.zsh uses).

if [ -n "${_ENV_SH_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
_ENV_SH_SOURCED=1

#############################################################################
# Exports (shared)

# XDG_CONFIG_HOME is re-set idempotently: .zshenv sets it first because
# ZDOTDIR depends on it; bash gets it here.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export EDITOR=nvim
export DOTFILES=$HOME/.local/share/chezmoi
export BUN_INSTALL="$HOME/.bun"
export PERSONAL_WIKI="$HOME/personal_wiki"
export LITELLM_BASE_URL="https://litellm.fluffy-walleye.ts.net"

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
# INITIALIZE HOMEBREW (wherever it lives)

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "Homebrew not installed, but chezmoi should have installed it!" >&2
fi

# brew shellenv already prepended these; record them so .zprofile can
# replay their priority after macOS path_helper reorders PATH
if [ -n "$HOMEBREW_PREFIX" ]; then
    add_to_path "$HOMEBREW_PREFIX/sbin"
    add_to_path "$HOMEBREW_PREFIX/bin"
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
# Path Management (user bins). ~/bin first (was bash-only — existence-guarded,
# so it is a no-op on machines without it; keeps bash's old priority order).

add_to_path "$HOME/bin"
add_to_path "$(brew --prefix postgresql@17)/bin"
add_to_path "$BUN_INSTALL/bin"
add_to_path "$HOME/.claude/local"
add_to_path "$HOME/.cargo/bin"
add_to_path "$HOME/.local/bin"
add_to_path "$HOME/.npm-global/bin"
add_to_path "$HOME/.lmstudio/bin"
add_to_path "$HOME/.amp/bin"

# Added by LM Studio CLI tool (lms)
add_to_path "$HOME/.lmstudio/bin"
