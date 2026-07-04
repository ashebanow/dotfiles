# -----------------------------------------------------
# jj — Jujutsu version control
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

  source <(COMPLETE=zsh jj)
fi
