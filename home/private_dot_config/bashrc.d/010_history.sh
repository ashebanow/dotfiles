# ~/.config/bashrc.d/010_history.sh — bash history
# 1:1 concept map of zsh's history.zsh setopts (BASH_UPGRADE §6).
# zsh: HIST_IGNORE_DUPS + HIST_IGNORE_SPACE -> HISTCONTROL=ignoredups:ignorespace
# zsh: SHARE_HISTORY append model -> shopt -s histappend

HISTFILE="$HOME/.bash_history"
HISTSIZE=10000
HISTFILESIZE=10000
HISTCONTROL=ignoredups:ignorespace
shopt -s histappend
