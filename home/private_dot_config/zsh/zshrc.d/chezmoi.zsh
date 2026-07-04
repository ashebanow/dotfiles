# -----------------------------------------------------
# chezmoi — dotfiles manager
# -----------------------------------------------------

if command -v chezmoi &> /dev/null; then
  alias c='chezmoi'
  alias ca='chezmoi apply'
  alias cadd='chezmoi add'
  alias cdc="cd $HOME/.local/share/chezmoi"
  alias cdccfg="cd $HOME/.local/share/chezmoi/home/private_dot_config"
  alias cdclocal="cd $HOME/.local/share/chezmoi/home/private_dot_local"
  alias cdiff='chezmoi diff'
  alias ce='chezmoi edit'
  alias cea='chezmoi edit --apply'
  alias ci='chezmoi init'
fi
