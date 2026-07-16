# -----------------------------------------------------
# Completion system — must be initialized before any of
# the tool completions sourced later (uv, devbox,
# tailscale, determinate-nixd, ...) call compdef
# -----------------------------------------------------

# Make Homebrew-provided completions available
if [[ -n "$HOMEBREW_PREFIX" && -d "$HOMEBREW_PREFIX/share/zsh/site-functions" ]]; then
  fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
fi

autoload -Uz compinit
compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"
