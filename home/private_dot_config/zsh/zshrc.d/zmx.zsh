# -----------------------------------------------------
# zmx — tmux session manager
# -----------------------------------------------------

if command -v zmx &> /dev/null; then
  eval "$(zmx completions zsh)"

  typeset -A short_host_names
  short_host_names[miraclemax]="mmax"
  short_host_names[aibot]="aibot"
  short_host_names[bergamot]="bmot"
  short_host_names[calamansi]="cala"
  short_host_names[limon]="lim"
  short_host_names[liquidity]="liq"
  short_host_names[yuzu]="yuzu"
  current_short_host_name="${short_host_names[`hostname -s`]:=`hostname -s`}"
  export ZMX_SESSION_PREFIX="${current_short_host_name}."

  alias ash="autossh -M 0 -q"
fi
