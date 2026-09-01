# ~/.config/shell/shortcuts.sh — personal cd shortcuts (PERSONAL-ONLY)
# Sourced by .bashrc.tmpl and .zshrc only on non-headless machines (gated
# by the .bashrc.tmpl headless conditional; zsh is excluded from headless
# entirely). These point at ashebanow's personal checkouts, which headless
# machines don't carry.

# cd to commonly used personal directories
alias cdwiki="cd \"$PERSONAL_WIKI\""
alias cdsecret="cd ~/Development/nix/secretspec/main.bitwarden-provider"
alias cdnix="cd ~/Development/nix/nix-config/main"
alias cdrds="cd ~/Development/ai/raindrop-skills"
alias cdsuwiki="cd ~/Development/boxboworg/suwiki/main"
