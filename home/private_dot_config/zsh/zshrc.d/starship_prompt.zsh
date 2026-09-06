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
# test them. This hook exports flags instead, and the [env_var.*] modules in
# starship.toml key off them at no cost (env_var forks nothing).
#
# Each gate is a PAIR of mutually exclusive variables, not one on|off value,
# because that is the only shape env_var can consume: it renders on set/unset
# and can never test a VALUE. Testing a value needs a [custom] module with a
# shell `when`, which forks per prompt -- the exact cost this hook exists to
# avoid. Exactly one variable of each pair is set at any time.
#
# THE HOOK MUST STAY SHELL-NATIVE: builtins, arithmetic and [[ ]] only -- no
# command substitutions, no external binaries. It runs before every prompt,
# so a single fork here would cancel out everything the env_var scheme saves.
#
# add-zsh-hook appends, and oh-my-zsh's starship plugin registered its own
# precmd back at `source $ZSH/oh-my-zsh.sh`, so this runs AFTER the variables
# above have been populated. Keep it that way.
#
# SINGLE SOURCE OF TRUTH for the thresholds that starship.toml mirrors as
# cmd_duration.min_time and jobs.threshold. ./check-starship.sh fails if the
# TOML side drifts from these values -- run it after changing either file.
STARSHIP_DURATION_THRESHOLD_MS=2000
STARSHIP_JOBS_THRESHOLD=1

export STARSHIP_NOALERT=1
export STARSHIP_AI_NONE=1
_starship_prompt_gates() {
  # Alert gate: open the block when the last command failed, ran long, or
  # left background jobs.
  local show=0
  # -n guard: on an empty line the integration unsets STARSHIP_CMD_STATUS and
  # starship gets --status="", hiding [status]. Without the guard the gate
  # would disagree and open an empty block.
  [[ -n ${STARSHIP_CMD_STATUS:-} && ${STARSHIP_CMD_STATUS} != 0 ]] && show=1
  (( ${STARSHIP_DURATION:-0} >= STARSHIP_DURATION_THRESHOLD_MS )) && show=1
  (( ${STARSHIP_JOBS_COUNT:-0} >= STARSHIP_JOBS_THRESHOLD )) && show=1
  if (( show )); then
    export STARSHIP_ALERT=1; unset STARSHIP_NOALERT
  else
    export STARSHIP_NOALERT=1; unset STARSHIP_ALERT
  fi

  # AI gate: robot badge when the CURRENT directory (deliberately not any
  # ancestor -- a parent repo's AGENTS.md should not light it up) has agent
  # instructions. [[ -f ]] is a builtin, so this replaces the `test` fork the
  # old custom.ai_none module paid on every prompt.
  if [[ -f AGENTS.md || -f CLAUDE.md ]]; then
    export STARSHIP_AI=1; unset STARSHIP_AI_NONE
  else
    export STARSHIP_AI_NONE=1; unset STARSHIP_AI
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _starship_prompt_gates
