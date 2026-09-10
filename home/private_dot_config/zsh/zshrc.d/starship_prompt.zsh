# 🌟 Starship prompt gates (zsh side)
#  BASED HEAVILY ON GATE DESIGN/IMPLEMENTATION IN:
#     https://github.com/russmckendrick/dotfiles/blob/main/starship.toml
#
# This file holds the ZSH registration of the starship prompt gates. The
# logic lives in shared files so BOTH shells run it -- `nix develop` spawns a
# BASH shell, so a zsh-only gate never fires inside one and the nix glyph
# silently disappears.
#
# Gates covered here:
#   - the ALERT gate (zsh-ONLY, defined below): the charcoal
#     duration/status/jobs block at the end. It reads STARSHIP_DURATION, which
#     zsh's starship precmd computes in place but bash's computes only at the
#     END of starship_precmd -- long after any user hook runs. So the alert
#     gate cannot see duration in bash without forking, and it stays zsh-only.
#   - the NIX gate (shared, sourced below): the nix glyph in the blue block,
#     env-based (IN_NIX_SHELL && !DEVENV_CMDLINE). Portable, so it lives in
#     shell/starship-nix-gate.sh and is registered here for zsh and in
#     bashrc.d/ for bash.
#   - (The robot badge / AI gate were retired -- [custom.ai] is a plain recipe
#     now.)
#
# The ALERT gate's input cannot be read by starship: exit status / duration /
# jobs arrive as CLI arguments (--status, --cmd-duration, --jobs), which the
# zsh integration keeps in STARSHIP_CMD_STATUS / STARSHIP_DURATION /
# STARSHIP_JOBS_COUNT -- plain shell variables, never exported. This hook
# exports a flag instead, and the [env_var.*] modules in starship.toml key off
# it at no cost (env_var forks nothing).
#
# The alert gate is a PAIR of mutually exclusive variables, not one on|off
# value, because that is the only shape env_var can consume: it renders on
# set/unset and can never test a VALUE. Testing a value needs a [custom]
# module with a shell `when`, which forks per prompt -- the exact cost this
# hook exists to avoid. Exactly one variable of the pair is set at any time.
#
# THE HOOKS MUST STAY SHELL-NATIVE: builtins, arithmetic and [[ ]] only -- no
# command substitutions, no external binaries. These gates run before every
# prompt, so a single fork there would cancel out everything the env_var
# scheme saves.
#
# _starship_alert_gate (precmd): exit status / duration / jobs change on every
# command, so this must run before every prompt.
#
# The gate skips its export/unset pair entirely when the state did not change
# since the last run. A stable prompt costs zero environment mutations; only a
# flip rewrites the environ. (The variables are pre-exported below so the
# "off" state needs no work on the first prompt either.)
#
# add-zsh-hook appends, and oh-my-zsh's starship plugin registered its own
# precmd back at `source $ZSH/oh-my-zsh.sh`, so the alert gate runs AFTER the
# variables above have been populated. Keep it that way.
#
# SINGLE SOURCE OF TRUTH for the thresholds that starship.toml mirrors as
# cmd_duration.min_time and jobs.threshold. ./check-starship.sh fails if the
# TOML side drifts from these values -- run it after changing either file.
STARSHIP_DURATION_THRESHOLD_MS=2000
STARSHIP_JOBS_THRESHOLD=1

# Establish the clean "off" state. For the alert PAIR, `unset` the "on"
# variable too: it may be inherited from a parent shell (a nested zsh, a tmux
# pane, or a starship run that exported it), and the state-transition guard
# below assumes exactly one variable of the pair starts unset. `unset` on an
# already-unset variable is a harmless no-op, so this is always safe.
export STARSHIP_NOALERT=1
unset STARSHIP_ALERT

# Alert gate (precmd): open the block when the last command failed, ran long,
# or left background jobs.
_starship_alert_gate() {
  local show=0
  # -n guard: on an empty line the integration unsets STARSHIP_CMD_STATUS and
  # starship gets --status="", hiding [status]. Without the guard the gate
  # would disagree and open an empty block.
  [[ -n ${STARSHIP_CMD_STATUS:-} && ${STARSHIP_CMD_STATUS} != 0 ]] && show=1
  (( ${STARSHIP_DURATION:-0} >= STARSHIP_DURATION_THRESHOLD_MS )) && show=1
  (( ${STARSHIP_JOBS_COUNT:-0} >= STARSHIP_JOBS_THRESHOLD )) && show=1
  if (( show )); then
    # Only rewrite the environ when the gate flips; a stable prompt must not
    # re-export/unset anything.
    if [[ -z ${STARSHIP_ALERT:-} ]]; then
      export STARSHIP_ALERT=1
      unset STARSHIP_NOALERT
    fi
  else
    if [[ -z ${STARSHIP_NOALERT:-} ]]; then
      export STARSHIP_NOALERT=1
      unset STARSHIP_ALERT
    fi
  fi
}

# Shared nix gate (env-based, both shells): defines _starship_nix_gate and the
# clean STARSHIP_NIX off-state. `nix develop` spawns bash, so this MUST be
# sourced in bash too (see .config/bashrc.d/starship-gate.sh).
source "$HOME/.config/shell/starship-nix-gate.sh"

# Seed the nix gate for the environment the shell started in, so the first
# prompt is correct before any precmd has run.
_starship_nix_gate

# NOTE: the gates are NOT registered here with `add-zsh-hook precmd`. This file
# is sourced from zshrc.d, which runs BEFORE hooks.sh (where `starship init`
# registers prompt_starship_precmd). add-zsh-hook appends, so registering here
# would put the gates BEFORE starship's precmd, and they would read a stale
# STARSHIP_CMD_STATUS -- one prompt behind. On a failed command that set
# NOALERT (blue cap) while [status] still drew a red ERROR. hooks.sh wraps
# prompt_starship_precmd instead, so the ordering is structural. Do not add
# add-zsh-hook lines back here.
