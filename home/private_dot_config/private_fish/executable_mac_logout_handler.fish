#!/opt/homebrew/bin/fish
# This script is intended to be run by MacOS launchctl on system load.
# It just sleeps until we get a signal, at which point it cleans up
# our bitwarden tokens.
function on_logout_signal --on-signal TERM --on-signal HUP --on-signal KILL
    set -e BW_SESSION
    set -e BWS_ACCESS_TOKEN
    exit
end

while true
    sleep 86400 &
    wait sleep
end
