###############################################################################
# General Aliases

if status is-interactive

    alias cls   'clear'
    alias cp    'cp -vi'
    alias cpv   'rsync -avh --info=progress2'
    alias gst   'git status -sb'
    alias mkdir 'mkdir -pv'
    alias mv    'mv -vi'
    alias nano  'vi'
    alias vi    'nvim'

    if set -q WSL_DISTRO_NAME
        set -g WSL_VSCODE_BIN_DIR '/mnt/c/Users/A Shebanow/AppData/Local/Programs/Microsoft VS Code Insiders/bin'
        alias code "/mnt/c/Users/A\ Shebanow/AppData/Local/Programs/Microsoft\ VS\ Code\ Insiders/bin/code-insiders"
    end

    if type -q jj
        alias jjdesc      'jj describe'
        alias jjfetch     'jj git fetch'
        alias jjlog       'jj log'
        alias jjmain      'jj bookmark set main --allow-backwards -r @'
        alias jjmainback  'jj bookmark set main --allow-backwards -r @-'
        alias jjmark      'jj bookmark'
        alias jjmarknew   'jj bookmark new'
        alias jjmarkset   'jj bookmark set'
        alias jjnew       'jj new'
        alias jjpush      'jj git push'
        alias jjst        'jj st'
    end

    if type -q atuin
        atuin init fish | source
    end

    if type -q bat
        alias cat   'bat --paging=never --style=plain'
        alias more  'bat'
    end

    if type -q chezmoi
        alias c         'chezmoi'
        alias ca        'chezmoi apply'
        alias cadd      'chezmoi add'
        alias cdc       "cd $HOME/.local/share/chezmoi"
        alias cdccfg    "cd $HOME/.local/share/chezmoi/home/private_dot_config"
        alias cdclocal  "cd $HOME/.local/share/chezmoi/home/private_dot_local"
        alias cdiff     'chezmoi diff'
        alias ce        'chezmoi edit'
        alias cea       'chezmoi edit --apply'
        alias ci        'chezmoi init'
    end

    if type -q delta
        alias diff 'delta'
    end

    if type -q duf
        alias df 'duf --only local'
    end

    if type -q eza
        alias eza   'eza --icons --group-directories-first'
        alias ls    'eza'
        alias la    'eza -a'
        alias ll    'eza -l'
        alias lla   'eza -al'
        alias ldot  'eza -d .??*'
        alias ldd   'eza -D --sort=mod'    # list directories, sort, descending, MODIFIED
        alias ldn   'eza -Dr'              # list directories, sort, descending, NAME
        alias lsD   'eza -r --sort=mod'    # sort, ascending, MODIFIED
        alias lsN   'eza -r'               # sort, ascending, name
        alias lsS   'eza -r --sort=size'   # sort, ascending, size
        alias lsd   'eza --sort=mod'       # sort, descending, MODIFIED
        alias lsn   'eza'                  # sort, descending, NAME
        alias lss   'eza --sort=size'      # sort, descending, SIZE
        alias lst   'eza --tree --level=2' # sort, descending, NAME && show directory tree
    end

    if type -q flatpak
        alias gearlever 'flatpak run it.mijorus.gearlever'
    end

    if type -q fzf
        alias v "fd --type f --hidden --exclude .git | fzf --preview 'bat {1}' | xargs vi"
    end

    if type -q just
        alias gust 'just -g'
        if type -q ujust
            alias ujc 'ujust --choose'
        end
    end

    if type -q tailscale
        alias tsa 'tailscale status --active'
    end

    if type -q thefuck
        thefuck --alias | source
    end

    if type -q zoxide
        alias cd 'z'
    end
end
