# -----------------------------------------------------
# Development tools: nvm, mise, uv, devbox, nix, just, tmux, bling, WSL
# -----------------------------------------------------

# mise — runtime & tool manager (replaced bin + bob)
if [[ -x ~/.local/bin/setup-mise.sh ]]; then
  ~/.local/bin/setup-mise.sh
fi
if command -v mise &> /dev/null; then
  eval "$(mise activate zsh)"
fi

# nvm — node version manager
export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# uv — Python package manager
if command -v uv &> /dev/null; then
  eval "$(uv generate-shell-completion zsh)"
  eval "$(uvx --generate-shell-completion zsh)"
fi

# devbox
if command -v devbox &> /dev/null; then
  eval "$(devbox completion zsh)"
fi

# Determinate Nix
if command -v determinate-nixd &> /dev/null; then
  eval "$(determinate-nixd completion zsh)"
fi

# just — command runner
if command -v just &> /dev/null; then
  alias gust='just -g'
  if command -v ujust &> /dev/null; then
    alias ujc='ujust --choose'
  fi
fi

# tmux
if command -v tmux &> /dev/null; then
  if [[ "$OSTYPE" == "linux-gnu"* ]] && grep -q '^ID_LIKE=.*arch' /etc/os-release 2>/dev/null; then
    export TMUX_PLUGIN_MANAGER_PATH="/usr/share/tmux-plugin-manager"
  else
    # on fedora, darwin, etc assume brew for now...
    export TMUX_PLUGIN_MANAGER_PATH="$(brew --prefix tpm)/share/tpm"
  fi
fi

# Bluefin/Bazzite CLI bling
### bling.sh source start
test -f /usr/share/ublue-os/bluefin-cli/bling.sh && source /usr/share/ublue-os/bluefin-cli/bling.sh
### bling.sh source end

# WSL — VS Code Insiders alias
if [[ -v WSL_DISTRO_NAME ]]; then
  alias code="/mnt/c/Users/A\ Shebanow/AppData/Local/Programs/Microsoft\ VS\ Code\ Insiders/bin/code-insiders"
fi

# Rust toolchain
. "$HOME/.cargo/env"
