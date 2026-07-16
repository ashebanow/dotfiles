# -----------------------------------------------------
# General aliases, navigation, and utility functions
# -----------------------------------------------------

# Man pages in neovim
export MANPAGER='nvim +Man!'

# Basic safety aliases
alias cls='clear'
alias cp='cp -vi'
alias cpv='rsync -avh --info=progress2'
alias diskspace='df -hl'
alias gst='git status -sb'
alias mkdir='mkdir -pv'
alias mv='mv -vi'
alias nano='vi'
alias vi='nvim'

# cd to commonly used directories
alias cdwiki="cd \"$PERSONAL_WIKI\""
alias cdlumq="cd ~/Development/nix/nix-config/lumquat"
alias cdzsh="cd ~/.local/share/chezmoi/home/private_dot_config/zsh"
alias cdrds="cd ~/Development/ai/raindrop-skills"
alias cdsuwiki="cd ~/Development/ai/suwiki/main"
