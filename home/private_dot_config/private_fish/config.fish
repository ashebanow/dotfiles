set -gx EDITOR      "nvim"
set -gx DOTFILES    "$HOME/.local/share/chezmoi"
set -gx BUN_INSTALL "$HOME/.bun"

fish_add_path -m "$HOME/.cargo/bin"
fish_add_path -m "$BUN_INSTALL/bin"
fish_add_path -m "$HOME/.npm-global/bin"
fish_add_path -m "$HOME/bin"
fish_add_path -m "$HOME/.local/bin"

# Load aliases
for file in (find $HOME/.config/fish/aliases -name '*.fish')
    source $file
end

if status is-interactive
    # Set greeting to fastfetch if available
    function fish_greeting
        if type -q fastfetch
            fastfetch
        else
            echo "Welcome to fish, the friendly interactive shell."
            echo "Fastfetch isn't installed yet!"
        end
    end
end
