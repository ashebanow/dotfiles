# ~/.config/shell/productivity.sh — shell productivity tools
# Shared by zsh and bash, every machine class. Plain POSIX shell; all
# command -v guarded (missing tools are simply skipped).

# -----------------------------------------------------
# bat — cat replacement
# -----------------------------------------------------

if command -v bat &> /dev/null; then
  alias cat='bat --paging=never --style=plain'
  alias more='bat'
fi

# -----------------------------------------------------
# duf — disk usage
# -----------------------------------------------------

if command -v duf &> /dev/null; then
  alias df='duf --only local'
fi

# -----------------------------------------------------
# fzf — fuzzy finder (init itself is in hooks.sh, keyed on $_SHELL_NAME)
# -----------------------------------------------------

export FZF_DEFAULT_OPTS=" \
  --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
  --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
  --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"

alias v="fd --type f --hidden --exclude .git | fzf --preview 'bat {1}' | xargs vi"

# -----------------------------------------------------
# eza — modern ls replacement.
# Normal aliases here; zsh's global-alias variants redefine these names
# in zshrc.d/eza.zsh (sourced later, so the -g forms win in zsh). Bash
# gets the plain command aliases (decided: equivalents where possible).
# -----------------------------------------------------

if command -v eza &> /dev/null; then
  alias eza='eza --icons --group-directories-first'
  alias ls='eza'
  alias la='eza -a'
  alias ll='eza -l'
  alias lla='eza -al'
  alias ldot='eza -d .??*'
  alias ldd='eza -D --sort=mod'
  alias ldn='eza -Dr'
  alias lsD='eza -r --sort=mod'
  alias lsN='eza -r'
  alias lsS='eza -r --sort=size'
  alias lsd='eza --sort=mod'
  alias lsn='eza'
  alias lss='eza --sort=size'
  alias lst='eza --tree --level=2'
fi
