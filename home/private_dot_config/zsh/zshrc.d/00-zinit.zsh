# -----------------------------------------------------
# Zinit — fast plugin manager
# -----------------------------------------------------

ZINIT_HOME="${XDG_DATA_HOME:-$HOME/.local/share}/zinit/zinit.git"

# Bootstrap zinit if not present
if [[ ! -f "$ZINIT_HOME/zinit.zsh" ]]; then
  print -P "%F{33}▓▒░ %F{220}Installing zinit…%f"
  command mkdir -p "$(dirname "$ZINIT_HOME")"
  command git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME" \
    && print -P "%F{33}▓▒░ %F{34}Zinit installed%f" \
    || { print -P "%F{160}▓▒░ Zinit installation failed%f"; return 1; }
fi

source "$ZINIT_HOME/zinit.zsh"

# Gruvbox dark theme for syntax-highlighting (set before plugin loads)
# Palette: morhetz/gruvbox — canonical bright colors
# Style: matches hue (github.com/grugq/hue) gruvbox-dark theme
local gb_fg='#ebdbb2' gb_fg2='#d5c4a1' gb_gray='#928374'
local gb_red='#fb4934' gb_green='#b8bb26' gb_yellow='#fabd2f' gb_blue='#83a598'
local gb_purple='#d3869b' gb_aqua='#8ec07c' gb_orange='#fe8019'

typeset -gA ZSH_HIGHLIGHT_STYLES=(
  default                       "fg=$gb_fg"
  unknown-token                 "fg=$gb_red,bold"
  reserved-word                 "fg=$gb_purple,bold"
  command                       "fg=$gb_green,bold"
  builtin                       "fg=$gb_aqua"
  alias                         "fg=$gb_green"
  function                      "fg=$gb_blue,bold"
  hashed-command                "fg=$gb_green"
  precommand                    "fg=$gb_aqua,bold"
  path                          "fg=$gb_fg,underline"
  path_pathseparator            "fg=$gb_gray"
  globbing                      "fg=$gb_orange"
  single-quoted-argument        "fg=$gb_yellow"
  double-quoted-argument        "fg=$gb_yellow"
  dollar-quoted-argument        "fg=$gb_yellow"
  dollar-double-quoted-argument "fg=$gb_aqua"
  back-quoted-argument          "fg=$gb_aqua"
  single-hyphen-option          "fg=$gb_orange"
  double-hyphen-option          "fg=$gb_orange"
  commandseparator              "fg=$gb_purple"
  redirection                   "fg=$gb_purple"
  assign                        "fg=$gb_yellow"
  history-expansion             "fg=$gb_purple,bold"
  comment                       "fg=$gb_gray,italic"
  bracket-error                 "fg=$gb_red,bold"
  bracket-level-1               "fg=$gb_blue"
  bracket-level-2               "fg=$gb_aqua"
  bracket-level-3               "fg=$gb_purple"
  bracket-level-4               "fg=$gb_orange"
  cursor-matchingbracket        "standout"
)

# Plugins
zinit ice wait"0" lucid depth=1
zinit light Giammarco-Ferranti/deja

zinit ice wait lucid
zinit light zsh-users/zsh-syntax-highlighting
