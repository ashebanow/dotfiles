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
typeset -A ZSH_HIGHLIGHT_STYLES
ZSH_HIGHLIGHT_STYLES[command]='fg=142,bold'               # bright green
ZSH_HIGHLIGHT_STYLES[builtin]='fg=142'                    # bright green
ZSH_HIGHLIGHT_STYLES[alias]='fg=142'                      # bright green
ZSH_HIGHLIGHT_STYLES[function]='fg=142'                   # bright green
ZSH_HIGHLIGHT_STYLES[precommand]='fg=142'                 # bright green
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=175'              # bright purple
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=214'       # bright yellow
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=214'       # bright yellow
ZSH_HIGHLIGHT_STYLES[path]='fg=109,underline'             # bright blue
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=109'                # bright blue
ZSH_HIGHLIGHT_STYLES[globbing]='fg=108'                   # bright aqua
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=142'     # bright green (strings)
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=142'     # bright green (strings)
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]='fg=208' # bright orange
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=175'   # bright purple
ZSH_HIGHLIGHT_STYLES[redirection]='fg=208'                # bright orange
ZSH_HIGHLIGHT_STYLES[comment]='fg=245'                    # gray
ZSH_HIGHLIGHT_STYLES[arg0]='fg=223'                       # fg1
ZSH_HIGHLIGHT_STYLES[default]='fg=223'                    # fg1
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=167,bold'         # bright red (errors)

# Plugins
zstyle ':autocomplete:*' verbose no

# Must load first — synchronous
zinit light marlonrichert/zsh-autocomplete

# Async plugin (styles set above)
zinit ice wait lucid
zinit light zsh-users/zsh-syntax-highlighting
