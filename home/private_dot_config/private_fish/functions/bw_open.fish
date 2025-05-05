function bw_open
    # Return if we have BW_SESSION defined AND this isn't the login shell.
    # Unfortunately on Mac everything is a login shell, so the optimization
    # doesn't work there.
   if test -n "$BW_SESSION"
        echo "Bitwarden is unlocked and ready to go!"
        return 0
    end

    if ! bw login --check &> /dev/null
        bw login "$BITWARDEN_EMAIL"
    end

    if ! bw unlock --check &> /dev/null
        set -Ux BW_SESSION (bw unlock --raw)
    end
end
