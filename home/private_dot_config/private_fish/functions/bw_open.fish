function bw_open
    # Check if we already have a valid session
    if set -q BW_SESSION; and test -n "$BW_SESSION"
        # Test if current session is still valid
        if BW_SESSION="$BW_SESSION" bw status >/dev/null 2>&1
            echo "Bitwarden is unlocked and ready to go!"
            return 0
        end
    end

    # Try to get session from our session manager
    set session_manager "$HOME/.local/bin/bw-session-manager"
    
    if test -x "$session_manager"
        # Use the keyring-based session manager
        set session_key ($session_manager ensure)
        if test $status -eq 0; and test -n "$session_key"
            set -Ux BW_SESSION "$session_key"
            echo "Bitwarden session established via keyring!"
            return 0
        end
    end

    # Fallback to manual unlock if session manager fails
    if ! bw unlock --check &>/dev/null
        if ! bw login --check &>/dev/null
            if test -n "$BITWARDEN_EMAIL"
                bw login "$BITWARDEN_EMAIL"
            else
                echo "Error: BITWARDEN_EMAIL not set and not logged in"
                return 1
            end
        end

        if ! bw unlock --check &>/dev/null
            set -Ux BW_SESSION (bw unlock --raw)
        end
    end
    
    echo "Bitwarden is unlocked and ready to go!"
end
