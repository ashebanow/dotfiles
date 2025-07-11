#!/usr/bin/env zsh
# This script is intended to be run by MacOS launchctl on system load.
# It just sleeps until we get a signal, at which point it cleans up
# our bitwarden tokens.

# Set up signal handlers for logout/shutdown
cleanup_on_exit() {
    unset BW_SESSION
    unset BWS_ACCESS_TOKEN
    exit
}

# Register signal handlers
trap cleanup_on_exit TERM HUP KILL

while true; do
    sleep 86400 &
    wait $!
done
