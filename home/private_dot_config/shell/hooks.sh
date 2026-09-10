# ~/.config/shell/hooks.sh — tool-init wiring, keyed on $_SHELL_NAME
# Sourced by .zshrc (after zshrc.d: compinit must precede the compdef calls)
# and by .bashrc (after the bashrc.d loop). Entrypoints set _SHELL_NAME;
# this file only substitutes it. Zero shell branches (audit 2026-09-01).

: "${_SHELL_NAME:=${SHELL##*/}}"   # fallback only; entrypoints set it explicitly

command -v direnv >/dev/null 2>&1           && eval "$(direnv hook "$_SHELL_NAME")"
command -v starship >/dev/null 2>&1         && eval "$(starship init "$_SHELL_NAME")"

# Starship prompt gates (zsh). The gates read STARSHIP_CMD_STATUS, which
# starship's own precmd (prompt_starship_precmd) computes in place. `add-zsh-hook
# precmd` order is NOT reliable -- devenv/direnv hooks and deja reorder the
# precmd_functions list -- so a separately-registered gate can run BEFORE
# starship's precmd and read a stale status, one prompt behind: on a failed
# command it sets NOALERT (blue cap) while [status] still draws a red ERROR.
#
# Wrap prompt_starship_precmd instead: keep the original and call the gates
# right after it sets the vars. The wrap is applied here (after `starship init`)
# so it is deterministic and immune to later hook reordering. zsh-only; bash
# needs no wrap because starship_precmd sets $? then evals STARSHIP_PROMPT_COMMAND
# before rendering PS1 (that path is registered in bashrc.d/starship-gate.sh).
# Gate definitions live in zshrc.d/starship_prompt.zsh (alert) and
# shell/starship-nix-gate.sh (nix), both sourced before this file. Keep the
# wrap shell-native (no subshell) so it costs no fork per prompt.
if [[ "$_SHELL_NAME" == "zsh" ]] && (( $+functions[prompt_starship_precmd] )); then
  functions[_starship_precmd_orig]=$functions[prompt_starship_precmd]
  prompt_starship_precmd() {
    _starship_precmd_orig
    _starship_alert_gate
    _starship_nix_gate
  }
fi
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
