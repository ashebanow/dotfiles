#!/bin/env bash

# first arg is the name of the project
PROJECT=$1
OWNER=${2:-ashebanow}

# create a new directory for the repository
mkdir "${PROJECT}" && cd "${PROJECT}"
# glone the repository (bare) and hide it in a hidden direcotry
git clone --bare git@github.com:"${OWNER}"/"${PROJECT}".git .bare
# create a `.git` file that points to the bare repo
echo "gitdir: ./.bare" > .git

git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git fetch
git for-each-ref --format='%(refname:short)' refs/heads | xargs -n1 -I{} git branch --set-upstream-to=origin/{}

git worktree add main
