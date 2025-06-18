function bw_open
   if bw unlock --check &> /dev/null
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
