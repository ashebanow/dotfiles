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

# -----------------------------------------------------
# wt — worktrunk: .bare scaffold repos (see boxboworg/AGENTS.md)
# -----------------------------------------------------

# wtregister — ensure wt places this repo's worktrees next to main/ (siblings
# of .bare), i.e. the [projects."<identifier>"] worktree-path entry wt would
# otherwise prompt for interactively. Run from anywhere inside the repo.
wtregister() {
  local cfg url ident
  cfg="${XDG_CONFIG_HOME:-$HOME/.config}/worktrunk/config.toml"
  url=$(git config --get remote.origin.url 2>/dev/null)
  if [ -z "$url" ]; then
    echo "wtregister: no origin remote configured" >&2
    return 1
  fi
  ident=$(printf '%s' "$url" | sed -E \
    -e 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' \
    -e 's#^[^@/]+@##' \
    -e 's#^([^/:]+):#\1/#' \
    -e 's#\.git$##')
  mkdir -p "$(dirname "$cfg")"
  if [ -f "$cfg" ] && grep -qF "[projects.\"$ident\"]" "$cfg"; then
    echo "wtregister: $ident already registered"
  else
    printf '\n[projects."%s"]\nworktree-path = "{{ repo_path }}/../{{ branch | sanitize }}"\n' \
      "$ident" >> "$cfg"
    echo "wtregister: registered $ident"
  fi
}

# newrepo — scaffold a .bare repo (boxboworg layout): <dir>/.bare store, .git
# anchor, and a worktree for the default branch at <dir>/<default-branch>.
#   newrepo <dir>                     scratch repo (empty commit on main)
#   newrepo <dir> <url|owner/repo>    clone an existing repo
newrepo() {
  if [ $# -lt 1 ]; then
    echo 'usage: newrepo <dir> [url|owner/repo]' >&2
    return 1
  fi
  local dir url branch tree commit
  dir="$1"
  url="${2:-}"
  mkdir -p "$dir" || return 1
  cd "$dir" || return 1
  if [ -n "$url" ]; then
    case "$url" in
      *://* | git@* | ssh://*)
        git clone --bare "$url" .bare || return 1
        ;;
      *)
        command -v gh >/dev/null 2>&1 || { echo 'newrepo: gh not installed' >&2; return 1; }
        gh repo clone --bare "$url" .bare || return 1
        ;;
    esac
  else
    git init --bare .bare -b main || return 1
    tree=$(git --git-dir=.bare mktree </dev/null) || return 1
    commit=$(git --git-dir=.bare commit-tree "$tree" -m 'Initial commit') || return 1
    git --git-dir=.bare update-ref refs/heads/main "$commit" || return 1
  fi
  printf 'gitdir: ./.bare\n' > .git
  branch=$(git --git-dir=.bare symbolic-ref --short HEAD)
  git worktree add "$branch" || return 1
  cd "$branch" || return 1
  echo "scaffolded: $PWD"
  if git config --get remote.origin.url >/dev/null 2>&1; then
    wtregister
  else
    echo 'note: no origin yet — after adding one, run: wtregister'
  fi
}

