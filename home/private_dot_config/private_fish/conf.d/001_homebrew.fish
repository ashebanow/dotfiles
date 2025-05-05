#############################################################################
# INITIALIZE HOMEBREW (wherever it lives)

if test -x /home/linuxbrew/.linuxbrew/bin/brew
  /home/linuxbrew/.linuxbrew/bin/brew shellenv fish | source
else if test -x /opt/homebrew/bin/brew
  /opt/homebrew/bin/brew shellenv fish | source
else
  echo "Homebrew not installed, but chezmoi should have installed it!"
  # exit
end
