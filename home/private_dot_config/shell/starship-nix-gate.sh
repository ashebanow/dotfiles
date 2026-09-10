# ~/.config/shell/starship-nix-gate.sh — nix glyph gate (shared, shell-agnostic)
# Sourced by BOTH .zshrc and .bashrc (via their per-shell hooks layer), because
# `nix develop` spawns a BASH shell (hard-coded in nix's develop.cc), so the
# nix glyph has to be computed there too -- a zsh-only gate never runs inside a
# nix develop subshell and the glyph silently never appears.
#
# Purely environment-based (no cwd scan, no fork): it reads the vars that nix
# and devenv already export and exports the single flag [env_var.nix] keys off.
# See the [env_var.nix] module in starship.toml for the consuming side.
#
# Why a SHELL gate and not a starship [custom] `when`: starship cannot AND two
# env vars, and a [custom] `when`/command forks per prompt. This hook is four
# builtin [[ ]] tests with no subshell. (The alert gate is NOT here -- it reads
# STARSHIP_DURATION, which zsh's starship precmd computes in-place but bash's
# computes only at the END of starship_precmd, after any user hook. So the
# alert gate is zsh-only and lives in zshrc.d/.)
#
# Seed/registration is per-shell (zsh: add-zsh-hook precmd; bash:
# PROMPT_COMMAND / STARSHIP_PROMPT_COMMAND) and lives alongside this source.
# This file only DEFINES the function and the flag's clean off-state.

# Clean off-state: env_var renders nothing when STARSHIP_NIX is unset, so the
# off state is simply "unset". Pre-unset it in case a parent shell exported it.
unset STARSHIP_NIX

# Show the nix glyph only in a REAL nix shell we entered explicitly -- `nix
# develop` or `nix shell` -- and not inside a devenv shell, because devenv also
# sets IN_NIX_SHELL=impure, which the builtin nix_shell module (and a naive
# IN_NIX_SHELL test) would take as a real nix shell and light up redundantly
# next to the custom.devenv glyph. The discriminator is DEVENV_CMDLINE, set
# only by devenv; a bare nix develop sets IN_NIX_SHELL with no DEVENV_* vars.
#
# devenv exits its shell (clearing DEVENV_* AND IN_NIX_SHELL) when you cd out
# of the project root, so "in a real nix shell" and "devenv owns this cd" never
# overlap: a devenv shell stays inside the project (so we never show nix there)
# and a bare nix develop never sets DEVENV_CMDLINE. The one case env-based
# distinguishes from file-based is a bare `nix develop` run INSIDE a directory
# that also has devenv.nix -- env-based shows the nix glyph (we are genuinely
# in nix), file-based would not.
_starship_nix_gate() {
  local show=0
  [[ -n ${IN_NIX_SHELL:-} && -z ${DEVENV_CMDLINE:-} ]] && show=1
  if (( show )); then
    [[ -z ${STARSHIP_NIX:-} ]] && export STARSHIP_NIX=1
  else
    [[ -n ${STARSHIP_NIX:-} ]] && unset STARSHIP_NIX
  fi
}
