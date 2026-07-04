# -----------------------------------------------------
# Shell tools: bat, direnv, duf, fzf, starship, thefuck, tv, deja, dircolors
# -----------------------------------------------------

# bat — cat replacement
if command -v bat &> /dev/null; then
  alias cat='bat --paging=never --style=plain'
  alias more='bat'
fi

# Custom dircolors
if [[ -f $HOME/.dircolors/dircolors ]]; then
  eval $(dircolors $HOME/.dircolors/dircolors)
fi

# direnv
if command -v direnv &> /dev/null; then
  eval "$(direnv hook zsh)"
fi

# duf — disk usage
if command -v duf &> /dev/null; then
  alias df='duf --only local'
fi

# fzf — fuzzy finder
if command -v fzf &> /dev/null; then
  export FZF_DEFAULT_OPTS=" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

  source <(fzf --zsh)

  alias v="fd --type f --hidden --exclude .git | fzf --preview 'bat {1}' | xargs vi"
fi

# starship — prompt
if command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
fi

# thefuck — command correction
if command -v thefuck &> /dev/null; then
  eval "$(thefuck --alias)"
fi

# tv — television (TUI tool)
if command -v tv &> /dev/null; then
  eval "$(tv init zsh)"
fi

# deja — directory jumper
if command -v deja &> /dev/null; then
  eval "$(deja init zsh)"
fi
