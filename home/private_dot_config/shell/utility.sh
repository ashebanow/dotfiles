# ~/.config/shell/utility.sh — utility functions and system tool aliases
# Shared by zsh and bash, every machine class. Plain POSIX shell; all
# command -v guarded (missing tools are simply skipped).

# -----------------------------------------------------
# Utility functions
# -----------------------------------------------------

# Archive extraction helper (existence-guarded so machines without it
# don't error)
if [ -f "$HOME/.local/bin/extract" ]; then
  source "$HOME/.local/bin/extract"
fi

# Custom dircolors
if [[ -f $HOME/.dircolors/dircolors ]]; then
  eval $(dircolors $HOME/.dircolors/dircolors)
fi

# -----------------------------------------------------
# System-level configs: tailscale, podman, autossh
# -----------------------------------------------------

# tailscale (completions in hooks.sh)
if command -v tailscale &> /dev/null; then
  alias tsa='tailscale status --active'
  alias tsb='tailscale status --web --active'
fi

# podman — container runtime (DOCKER_HOST wiring needs podman machine; disabled)
# if command -v podman &> /dev/null; then
#   export DOCKER_HOST="`podman info -f json |jq -r '.host.remoteSocket.path'`"
#   export DOCKER_HOST="unix://`podman machine inspect --format '.ConnectionInfo.PodmanSocket.Path'`"
# fi

# autossh (tmux session helper)
alias ash="autossh -M 0 -q"

# -----------------------------------------------------
# zmx — tmux session manager host-name map (portable case function, no
# zsh assoc array; bash gets ZMX_SESSION_PREFIX too). Completions live in
# hooks.sh. Function, not an inline `case` inside $( ): macOS bash 3.2
# cannot parse `case` inside a command substitution in double quotes.
# -----------------------------------------------------

_zmx_short_host() {
  case "$(hostname -s)" in
    miraclemax) printf %s mmax ;;
    aibot) printf %s aibot ;;
    bergamot) printf %s bmot ;;
    calamansi) printf %s cala ;;
    limon) printf %s lim ;;
    liquidity) printf %s liq ;;
    yuzu) printf %s yuzu ;;
    *) hostname -s ;;
  esac
}

if command -v zmx &> /dev/null; then
  export ZMX_SESSION_PREFIX="$(_zmx_short_host)."
fi
