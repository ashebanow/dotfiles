# -----------------------------------------------------
# Version control: gh, worktrunk
# -----------------------------------------------------

# GitHub CLI
if command -v gh &> /dev/null; then
  eval "$(gh completion -s zsh)"
  if ! gh extension list | grep -q gh-copilot; then
    eval "$(gh copilot alias -- zsh)"
  fi
fi

# worktrunk
if command -v wt >/dev/null 2>&1; then
  eval "$(command wt config shell init zsh)"
fi
