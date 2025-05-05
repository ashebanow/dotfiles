set -gx EDITOR      "nvim"
set -gx DOTFILES    "$HOME/.local/share/chezmoi"
set -gx BUN_INSTALL "$HOME/.bun"

fish_add_path -m -p -g "$HOME/.local/bin"
fish_add_path -g "$HOME/.cargo/bin"
fish_add_path -g "$BUN_INSTALL/bin"

# TODO: install plugins on first use using 'fisher update'

# Load aliases
for file in (find $HOME/.config/fish/aliases -name '*.fish')
    source $file
end

if status is-interactive
    # Set greeting to fastfetch if available
    function fish_greeting
        echo "Welcome to fish, the friendly interactive shell."
        if type -q fastfetch
            fastfetch
        else
            echo "You need to install fastfetch!"
        end
    end
end
