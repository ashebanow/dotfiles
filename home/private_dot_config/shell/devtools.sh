# ~/.config/shell/devtools.sh — personal development tools (PERSONAL-ONLY)
# Sourced by .bashrc.tmpl and .zshrc only on non-headless machines (gated
# by the .bashrc.tmpl headless conditional; zsh is excluded from headless
# entirely). Never sourced on headless — this is what keeps the brew warning
# off headless machines. Plain POSIX shell; brew/nvm/cargo adds are guarded
# or existence-checked as they always were.

#############################################################################
# INITIALIZE HOMEBREW (wherever it lives) — brew is personal-only, so this
# block (and its "not installed" warning) never runs on headless machines.

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

# NOTE (BOX-128): devtools.sh runs after paths.sh, so brew shellenv
# prepends its bins ahead of the nix/user-bin entries added there — brew
# now takes PATH priority over nix on personal machines (previously nix
# was first, per the original env.sh init order). Measured impact on
# miracle_max: brew's bins overlap nix by only `brew` itself, so no nix
# tool is shadowed. Restoring the old priority portably would need a
# shell branch (zsh doesn't split unquoted expansions on IFS), which the
# shared chunks forbid. Revisit only if a personal machine's brew ever
# grows meaningful overlaps with nix.

# postgres (brew keg) — needs brew, so it lives here with the brew init
add_to_path "$(brew --prefix postgresql@17)/bin"

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
  else
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

. "$HOME/.cargo/env"
