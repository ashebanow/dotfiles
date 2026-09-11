# ~/.config/shell/env.sh — shared environment exports (zsh and bash, POSIX)
# Sourced by .zshenv (every zsh) and by .bashrc (interactive bash).
# Exports ONLY: ~/-relative variables that work for any user — no secrets,
# no PATH logic, no tool init (those live in paths.sh / the chunk files).
# Idempotent via the _ENV_SH_SOURCED guard (same pattern paths.zsh uses).

if [ -n "${_ENV_SH_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
_ENV_SH_SOURCED=1

# XDG_CONFIG_HOME is re-set idempotently: .zshenv sets it first because
# ZDOTDIR depends on it; bash gets it here.
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export EDITOR=nvim
export DOTFILES=$HOME/.local/share/chezmoi
export PERSONAL_WIKI="$HOME/personal_wiki"
# Base URL of the LLM gateway, for anything that wants to reach models. Named
# for what it does rather than for a product, so a future gateway swap does not
# move the endpoint. Provider API keys are deliberately not exported: clients
# reach models through the gateway, which holds the keys.
export AI_BASE_URL="https://ai.fluffy-walleye.ts.net"
