# ~/.config/shell/devtools.sh — personal development tools (PERSONAL-ONLY)
# Sourced by .bashrc.tmpl and .zshrc only on non-headless machines (gated
# by the .bashrc.tmpl headless conditional; zsh is excluded from headless
# entirely). Never sourced on headless — this is what keeps the brew warning
# off headless machines. Plain POSIX shell; every brew/nvm/cargo add is
# existence-checked, not assumed (paths.sh's rule: a machine without the tool
# skips it and stays quiet).
#
# Chezmoi-wise this stays a plain script, not a template: this file already
# branches on $OSTYPE at runtime (the tmux block below), and the Homebrew
# warning is the same kind of check. brew is a macOS tool in this world — on
# Linux, nix installs the packages (CONTEXT.md, "nix owns package
# installation"), so a missing brew there is normal and must not warn. That
# warning used to fire on every NixOS desktop shell. The /home/linuxbrew probe
# stays for legacy Linuxbrew machines; they simply stop being scolded when the
# keg is absent.

#############################################################################
# INITIALIZE HOMEBREW (wherever it lives) — brew is personal-only, so this
# block (and its "not installed" warning) never runs on headless machines.

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ "$(uname -s)" = "Darwin" ]; then
    # darwin only: there chezmoi/nix-darwin are expected to have provided
    # Homebrew, so its absence is a real fault worth reporting. On Linux it is
    # not — nix owns packages (header), so say nothing.
    echo "Homebrew not installed, but chezmoi should have installed it!" >&2
fi


# brew shellenv already prepended these; record them so .zprofile can
# replay their priority after macOS path_helper reorders PATH
if [ -n "$HOMEBREW_PREFIX" ]; then
    add_to_path "$HOMEBREW_PREFIX/sbin"
    add_to_path "$HOMEBREW_PREFIX/bin"
fi

# NOTE (BOX-128): devtools.sh runs after paths.sh, so brew shellenv
# prepends its bins ahead of the nix/user-bin entries added there — brew
# now takes PATH priority over nix on personal machines (previously nix
# was first, per the original env.sh init order). Measured impact on
# miracle_max: brew's bins overlap nix by only `brew` itself, so no nix
# tool is shadowed. Restoring the old priority portably would need a
# shell branch (zsh doesn't split unquoted expansions on IFS), which the
# shared chunks forbid. Revisit only if a personal machine's brew ever
# grows meaningful overlaps with nix.

# postgres (brew keg) — brew-only, so it is existence-guarded like every other
# path add. This used to call `brew` unconditionally and errored on NixOS.
if command -v brew >/dev/null 2>&1; then
    pg_prefix=$(brew --prefix postgresql@17 2>/dev/null)
    [ -n "$pg_prefix" ] && add_to_path "$pg_prefix/bin"
fi

#############################################################################
# nvm — node version manager
# -----------------------------------------------------

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

#############################################################################
# tmux — plugin manager path
# -----------------------------------------------------

if command -v tmux &> /dev/null; then
  if [[ "$OSTYPE" == "linux-gnu"* ]] && grep -q '^ID_LIKE=.*arch' /etc/os-release 2>/dev/null; then
    export TMUX_PLUGIN_MANAGER_PATH="/usr/share/tmux-plugin-manager"
  elif command -v brew &> /dev/null; then
    # on fedora, darwin, etc assume brew for now...
    export TMUX_PLUGIN_MANAGER_PATH="$(brew --prefix tpm)/share/tpm"
  fi
fi

#############################################################################
# Bluefin/Bazzite CLI bling
# -----------------------------------------------------

### bling.sh source start
test -f /usr/share/ublue-os/bluefin-cli/bling.sh && source /usr/share/ublue-os/bluefin-cli/bling.sh
### bling.sh source end

#############################################################################
# WSL — VS Code Insiders alias (portable test: bash 3.2 on macOS lacks
# `[[ -v ]]`, so use -n instead)
# -----------------------------------------------------

if [[ -n "${WSL_DISTRO_NAME-}" ]]; then
  alias code="/mnt/c/Users/A\ Shebanow/AppData/Local/Programs/Microsoft\ VS\ Code\ Insiders/bin/code-insiders"
fi

#############################################################################
# Rust toolchain
# -----------------------------------------------------

# rustup's env file, when rustup is installed outside nix. A nix-provided
# rustc/cargo needs no env file, so this is existence-checked rather than
# assumed — sourcing it unconditionally failed on every NixOS shell. Spelled as
# an if-block, not `[ -f ... ] && . ...`, so the file ends on a zero status: as
# the last line, the test's failure would leak out to whatever sourced us.
if [ -f "$HOME/.cargo/env" ]; then
    . "$HOME/.cargo/env"
fi
