#!/usr/bin/env bash

if command -v bob >/dev/null 2>&1; then
  mkdir -p $(brew --prefix)/etc/bash_completion.d
  bob complete bash >$(brew --prefix)/etc/bash_completion.d/bob.bash-completion
fi
