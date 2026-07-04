# -----------------------------------------------------
# eza — modern ls replacement
# -----------------------------------------------------

if command -v eza &> /dev/null; then
  alias eza='eza --icons --group-directories-first'
  alias ls='eza'
  alias la='eza -a'
  alias ll='eza -l'
  alias lla='eza -al'
  alias ldot='eza -d .??*'
  alias -g ldd='eza -D --sort=mod'    # list directories, sort, descending, MODIFIED
  alias -g ldn='eza -Dr'              # list directories, sort, descending, NAME
  alias -g lsD='eza -r --sort=mod'    # sort, ascending, MODIFIED
  alias -g lsN='eza -r'               # sort, ascending, name
  alias -g lsS='eza -r --sort=size'   # sort, ascending, size
  alias -g lsd='eza --sort=mod'       # sort, descending, MODIFIED
  alias -g lsn='eza'                  # sort, descending, NAME
  alias -g lss='eza --sort=size'      # sort, descending, SIZE
  alias -g lst='eza --tree --level=2' # sort, descending, NAME && show directory tree
fi
