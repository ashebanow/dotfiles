#!env bash

declare -a omp_themes_dir
case "$(uname -s)" in
Darwin)
    omp_themes_dir=$(brew --prefix oh-my-posh)/themes
    ;;
Linux)
    omp_themes_dir=$HOME/themes
    ;;
esac

themes=(catppuccin catppuccin_mocha bubblesextra tokyo tokyonight_storm)
for theme in "${themes[@]}"; do
    echo "Exporting $theme"
    oh-my-posh config export \
        --config $omp_themes_dir/$theme.omp.json \
        --output $theme.omp.toml
done
