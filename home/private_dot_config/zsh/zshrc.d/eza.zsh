# -----------------------------------------------------
# eza — modern ls replacement
# The plain aliases (ls, la, ll, ...) live in shared rc.sh. These are the
# zsh-only GLOBAL aliases (bash has no global-alias concept); they redefine
# the same names as plain aliases in rc.sh (sourced earlier), upgrading
# them to global form in zsh. Bash uses the plain-command equivalents.
# -----------------------------------------------------

if command -v eza &> /dev/null; then
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
