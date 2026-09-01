# ~/.config/bashrc.d/020-prompt.sh — plain PS1 (no starship)
# Replaces starship on headless machines (starship is not part of the
# headless toolset). Harmless on personal bash: hooks.sh's starship init
# runs later and overrides PS1 there.
#
# Spec (BOX-128):
#   - user@host always visible; GREEN normally, RED when dangerous.
#     Dangerous = running as root (EUID 0).
#   - subshell marker "(nix-dev)" shown when IS_NIX_DEVELOP or IN_NIX_SHELL
#     is set (the nix-config devshell will export IS_NIX_DEVELOP in a
#     second-repo follow-up; IN_NIX_SHELL is nix shell's own var).
#   - no starship, no plugin manager, no external tools.
#   - ANSI escapes wrapped in \[ \] so readline can compute line length.
# bash-only (it lives in bashrc.d; zsh keeps its own prompt setup).

if [ "$EUID" -eq 0 ]; then
  # root — dangerous, red
  PS1='\[\e[0;31m\]\u@\h\[\e[0m\]'
else
  # normal — green
  PS1='\[\e[0;32m\]\u@\h\[\e[0m\]'
fi

if [ -n "${IS_NIX_DEVELOP:-}" ] || [ -n "${IN_NIX_SHELL:-}" ]; then
  PS1="$PS1"' \[\e[1;36m\](nix-dev)\[\e[0m\]'
fi

# \$ renders $ for normal users, # for root
PS1="$PS1"' \$ '
