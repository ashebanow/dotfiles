# 🌟 Starship prompt gates
# Drives the conditional segments of the prompt bar: the charcoal
# duration/status/jobs "alert" block at the end, and the robot badge shown in
# folders that carry agent instructions. Each one vanishes completely when its
# condition is off.
#
# starship receives the exit status, command duration and job count as CLI
# arguments (--status, --cmd-duration, --jobs). The zsh integration keeps them
# in STARSHIP_CMD_STATUS / STARSHIP_DURATION / STARSHIP_JOBS_COUNT, which are
# plain shell variables and are never exported -- so no starship module can
# test them. These hooks export flags instead, and the [env_var.*] modules in
# starship.toml key off them at no cost (env_var forks nothing).
#
# Each gate is a PAIR of mutually exclusive variables, not one on|off value,
# because that is the only shape env_var can consume: it renders on set/unset
# and can never test a VALUE. Testing a value needs a [custom] module with a
# shell `when`, which forks per prompt -- the exact cost these hooks exist to
# avoid. Exactly one variable of each pair is set at any time.
#
# THE HOOKS MUST STAY SHELL-NATIVE: builtins, arithmetic and [[ ]] only -- no
# command substitutions, no external binaries. The alert gate runs before
# every prompt, so a single fork there would cancel out everything the
# env_var scheme saves.
#
# Two hooks, split by how often their input changes:
#   - _starship_alert_gate (precmd): exit status / duration / jobs change on
#     every command, so this must run before every prompt.
#   - _starship_ai_gate (chpwd): AGENTS.md / CLAUDE.md only change when the
#     directory changes, so it runs once per cd -- never on an ordinary
#     prompt -- and is seeded once at load for the directory the shell starts
#     in. This removes the only syscall (the [[ -f ]] stat) from the
#     per-prompt path. The price: if a marker file is created/removed in the
#     CURRENT directory without a cd, the badge goes stale until the next cd.
#
# Both gates skip their export/unset pair entirely when the state did not
# change since the last run. A stable prompt costs zero environment mutations;
# only a flip rewrites the environ. (The variables are pre-exported below so
# the "off" state needs no work on the first prompt either.)
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

# Establish the clean "off" state for both pairs. `unset` the "on" variables
# too: they may be inherited from a parent shell (a nested zsh, a tmux pane,
# or a starship run that exported them), and the state-transition guards
# below assume exactly one variable of each pair starts unset. `unset` on an
# already-unset variable is a harmless no-op, so this is always safe.
export STARSHIP_NOALERT=1
export STARSHIP_AI_NONE=1
unset STARSHIP_ALERT STARSHIP_AI

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

# AI gate (chpwd): robot badge when the CURRENT directory (deliberately not
# any ancestor -- a parent repo's AGENTS.md should not light it up) has agent
# instructions. [[ -f ]] is a builtin, so this replaces the `test` fork the
# old custom.ai_none module paid on every prompt; hooking it to chpwd removes
# the stat from the per-prompt path entirely.
_starship_ai_gate() {
  if [[ -f AGENTS.md || -f CLAUDE.md ]]; then
    if [[ -z ${STARSHIP_AI:-} ]]; then
      export STARSHIP_AI=1
      unset STARSHIP_AI_NONE
    fi
  else
    if [[ -z ${STARSHIP_AI_NONE:-} ]]; then
      export STARSHIP_AI_NONE=1
      unset STARSHIP_AI
    fi
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _starship_alert_gate
add-zsh-hook chpwd _starship_ai_gate
# Seed the AI gate for the directory the shell starts in, so the first prompt
# is correct before any cd has fired chpwd.
_starship_ai_gate
