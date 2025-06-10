#!/usr/bin/env bash

# setup common to all install scripts
source "install_common.sh"

# vscode utilities
source "../vscode_utils.sh"

function install_distrobox_if_needed() {
    if command -v distrobox; then
        return 0
    end

    # TODO: install distrobox
    return 0
}

# Parameters:
#
#   $1: name          Optional        Default: <container-name>.$(uname -n)
#   $2: hostname      Optional        Default: ${container_name_default}
#   $2: image         Optional        Default: ${container_image_default}
#   $5: options       Optional        Default: N/A
#
# 'options' parameter is a dict, with the following fields. All fields are optional
# and can be ommitted if you don't need them.
#
# additional_packages     Default: N/A        Example: "git vim tmux nodejs"
# command                 Default: bash
# home                    Default: directory_path
# init                    Default: false
# start_now               Default: true
# init_hooks              Default: N/A        Example: "touch /init-normal"
# nvidia                  Default: false
# pre_init_hooks          Default: N/A        Example: "touch /pre-init"
# pull                    Default: true
# root                    Default: false
# replace                 Default: false
# volume                  Default: N/A        Example: "/tmp/test:/run/a /tmp/test:/run/b"

function create_distrobox() {
    # TODO: validate arguments
    # distrobox create -n $1 -i $2
}
