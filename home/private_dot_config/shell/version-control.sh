# ~/.config/shell/version-control.sh — git/version-control aliases
# Shared by zsh and bash, every machine class. Plain POSIX shell; all
# command -v guarded.

# -----------------------------------------------------
# just — command runner (git-style task runner)
# -----------------------------------------------------

if command -v just &> /dev/null; then
  alias gust='just -g'
  if command -v ujust &> /dev/null; then
    alias ujc='ujust --choose'
  fi
fi

# -----------------------------------------------------
# jj — Jujutsu version control (completions in hooks.sh)
# -----------------------------------------------------

if command -v jj &> /dev/null; then
  alias jjdesc='jj describe'
  alias jjfetch='jj git fetch'
  alias jjlog='jj log'
  alias jjmain='jj bookmark set main --allow-backwards -r @'
  alias jjmainback='jj bookmark set main --allow-backwards -r @-'
  alias jjmark='jj bookmark'
  alias jjmarknew='jj bookmark new'
  alias jjmarkset='jj bookmark set'
  alias jjnew='jj new'
  alias jjpush='jj git push'
  alias jjst='jj st'
fi
