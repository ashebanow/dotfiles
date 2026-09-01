# ~/.config/shell/hooks.sh — tool-init wiring, keyed on $_SHELL_NAME
# Sourced by .zshrc (after zshrc.d: compinit must precede the compdef calls)
# and by .bashrc (after the bashrc.d loop). Entrypoints set _SHELL_NAME;
# this file only substitutes it. Zero shell branches (audit 2026-09-01).

: "${_SHELL_NAME:=${SHELL##*/}}"   # fallback only; entrypoints set it explicitly

command -v direnv >/dev/null 2>&1           && eval "$(direnv hook "$_SHELL_NAME")"
command -v starship >/dev/null 2>&1         && eval "$(starship init "$_SHELL_NAME")"
command -v tv >/dev/null 2>&1               && eval "$(tv init "$_SHELL_NAME")"
command -v gh >/dev/null 2>&1               && eval "$(gh completion -s "$_SHELL_NAME")"
command -v gh >/dev/null 2>&1 && gh copilot --version >/dev/null 2>&1 && eval "$(gh copilot alias -- "$_SHELL_NAME")"
command -v uv >/dev/null 2>&1               && eval "$(uv generate-shell-completion "$_SHELL_NAME")"
command -v uvx >/dev/null 2>&1              && eval "$(uvx --generate-shell-completion "$_SHELL_NAME")"
command -v devbox >/dev/null 2>&1           && eval "$(devbox completion "$_SHELL_NAME")"
command -v determinate-nixd >/dev/null 2>&1 && eval "$(determinate-nixd completion "$_SHELL_NAME")"
command -v devenv >/dev/null 2>&1           && eval "$(devenv hook "$_SHELL_NAME")"
command -v tailscale >/dev/null 2>&1        && eval "$(tailscale completion "$_SHELL_NAME")"
command -v wt >/dev/null 2>&1               && eval "$(command wt config shell init "$_SHELL_NAME")"
command -v zmx >/dev/null 2>&1              && eval "$(zmx completions "$_SHELL_NAME")"
command -v jj >/dev/null 2>&1               && eval "$(COMPLETE="$_SHELL_NAME" jj)"
command -v thefuck >/dev/null 2>&1          && eval "$(thefuck --alias)"
command -v fzf >/dev/null 2>&1              && eval "$(fzf --$_SHELL_NAME)"
