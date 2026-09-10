# ~/.config/bashrc.d/starship-gate.sh — bash registration of the nix prompt gate
# Sourced by ~/.bashrc (the bashrc.d loop), which runs BEFORE hooks.sh initializes
# starship. This defines the nix gate function and stitches it into the prompt.
#
# WHY bash needs this: `nix develop` spawns a BASH shell (hard-coded in nix's
# develop.cc), which sources ~/.bashrc but never zsh's zshrc.d/. A zsh-only nix
# gate would never run there, so the nix glyph silently never appears. This
# mirrors the zsh registration (zshrc.d/starship_prompt.zsh).
#
# HOW the hook survives starship init: we append `_starship_nix_gate` to
# PROMPT_COMMAND here, BEFORE hooks.sh runs `starship init bash`. That init
# (line ~130) sees an existing PROMPT_COMMAND, moves it verbatim into
# STARSHIP_PROMPT_COMMAND, and sets PROMPT_COMMAND="starship_precmd". starship's
# starship_precmd evals STARSHIP_PROMPT_COMMAND just before it renders PS1, so
# our gate runs every prompt -- no fork, no clobber. (Setting it directly as
# STARSHIP_PROMPT_COMMAND here would NOT survive, because that init overwrites
# that variable wholesale.)
#
# NOTE: the ALERT gate is NOT registered here. It reads STARSHIP_DURATION, which
# bash's starship_precmd computes only at the very END of the function -- long
# after STARSHIP_PROMPT_COMMAND runs -- so it cannot see duration in bash. The
# alert block is zsh-only by design (see zshrc.d/starship_prompt.zsh).

# Define _starship_nix_gate + the clean STARSHIP_NIX off-state (idempotent).
if ! declare -F _starship_nix_gate >/dev/null 2>&1; then
  source "$HOME/.config/shell/starship-nix-gate.sh"
fi

# Seed for the environment this shell started in, so the first prompt is right.
_starship_nix_gate

# Register the gate as a per-prompt hook, without duplicating it.
if [[ -z "${PROMPT_COMMAND:-}" ]]; then
  PROMPT_COMMAND='_starship_nix_gate'
elif [[ "${PROMPT_COMMAND}" != *"_starship_nix_gate"* ]]; then
  PROMPT_COMMAND="${PROMPT_COMMAND}; _starship_nix_gate"
fi
export PROMPT_COMMAND
