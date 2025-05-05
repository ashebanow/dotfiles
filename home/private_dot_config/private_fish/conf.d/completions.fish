###############################################################################
# Set up completions and other settings for installed programs that need it.

if status is-interactive
    # Commands to run in interactive sessions can go here
    if type -q devbox
        devbox completion fish | source
    end

    if test -f $HOME/.dircolors/dircolors
        dircolors $HOME/.dircolors/dircolors | source
    end

    if type -q direnv
        direnv hook fish | source
    end

    #### FZF
    # See https://github.com/catppuccin/fzf for theming info and other
    # catppucin variants.
    if type -q fzf
        set -Ux FZF_DEFAULT_OPTS "\
        --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
        --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
        --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
        --color=selected-bg:#45475a \
        --color=border:#313244,label:#cdd6f4"

        # Set up fzf key bindings
        fzf --fish | source
    end

    if type -q gh
        gh completion -s fish | source
        if ! gh extension list | grep -q gh-copilot
            gh copilot alias -- fish | source
        end
    end

    if type -q op
        op completion fish | source
    end

    if type -q orb
        orb completion fish | source
    end

    # if type -q starship
    #     starship init fish | source
    # end

    if type -q tailscale
        tailscale completion fish | source
    end

    if type -q tmux
        if type -q brew
            set -gx TMUX_PLUGIN_MANAGER_PATH "$(brew --prefix tpm)/share/tpm"
        else
            # for arch linux and other places where we don't have homebrew
            set -gx TMUX_PLUGIN_MANAGER_PATH "/usr/share/tmux-plugin-manager"
        end
    end

    if type -q zoxide
        zoxide init fish | source
    end
end
