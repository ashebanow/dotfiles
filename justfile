#!/usr/bin/env just --justfile

# Recipes for working on THIS chezmoi dotfiles repo.
#
# `just` uses the nearest justfile found while searching upward, so being
# inside this repo shadows the global ~/.justfile (installed by chezmoi
# from home/dot_justfile.tmpl). Import it so the global recipes (chezmoi
# update-config, pi-update, nix-config clean/dry-run/switch/build-hm/...)
# stay visible and runnable here too. Recipes defined in THIS file are the
# chezmoi-repo-specific ones; note `build` (chezmoi apply) is the same
# operation as the imported update-config.

import "~/.justfile"

# Build the dotfiles: apply this repo's managed files to the current
# machine (chezmoi apply). Same as update-config, kept under the name you
# reach for when developing this repo.
build:
    chezmoi apply

# For testing, make chezmoi forget about script run state
clear-chezmoi-script-state:
    chezmoi state delete-bucket --bucket=scriptState
