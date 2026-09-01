#!/usr/bin/zsh

# Smart PATH management functions
# Features:
# - Validates directory exists
# - Normalizes paths (resolves ~, $HOME, XDG vars, etc.)
# - Prevents duplicates using canonical paths
# - Handles symbolic links intelligently
# - Provides informative feedback

# make sure we don't get included twice
[[ -n "$_PATHS_HELPERS_INCLUDED" ]] && return
_PATHS_HELPERS_INCLUDED=1

# Ordered record of every add_to_path/add_to_path_end request made in
# this shell. Replayed by replay_path_adds from $ZDOTDIR/.zprofile to
# restore our intended ordering after macOS path_helper (/etc/zprofile)
# reorders PATH behind our back.
typeset -ga _path_adds _path_end_adds

# Internal helper: Get canonical path
_get_canonical_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path"
    else
        # Fallback for systems without realpath
        (cd "$path" && pwd -P)
    fi
}

# Internal helper: Get array of canonical paths currently in PATH
_get_canonical_path_array() {
    local -a current_paths
    local -a canonical_paths
    local path_component canonical_component

    IFS=':' read -A current_paths <<< "$PATH"

    for path_component in "${current_paths[@]}"; do
        if [[ -d "$path_component" ]]; then
            canonical_component=$(_get_canonical_path "$path_component" 2>/dev/null)
            [[ -n "$canonical_component" ]] && canonical_paths+=("$canonical_component")
        fi
    done

    # Return array via global variable (zsh limitation)
    _canonical_paths=("${canonical_paths[@]}")
}

# Core validation and normalization logic
_validate_and_normalize_path() {
    local target_dir="$1"
    local usage_msg="$2"
    local debug="$3"

    # Validate input
    if [[ -z "$target_dir" ]]; then
        echo "$usage_msg" >&2
        return 1
    fi

    [[ "$debug" == "true" ]] && echo "Debug: Input path: $target_dir" >&2

    # Expand and normalize the path
    local expanded_dir
    expanded_dir=$(eval echo "$target_dir")

    [[ "$debug" == "true" ]] && echo "Debug: Expanded path: $expanded_dir" >&2

    # Check if directory exists
    if [[ ! -d "$expanded_dir" ]]; then
        # normally a silent error since its very common across systems
        [[ "$debug" == "true" ]] && echo "Debug: Directory '$target_dir' does not exist" >&2
        return 1
    fi

    # Get canonical path
    local canonical_dir
    canonical_dir=$(_get_canonical_path "$expanded_dir")

    [[ "$debug" == "true" ]] && echo "Debug: Canonical path: $canonical_dir" >&2

    # Export results via global variables (set before the duplicate
    # check so callers can still record already-present dirs for replay)
    _validated_target_dir="$target_dir"
    _validated_expanded_dir="$expanded_dir"
    _validated_canonical_dir="$canonical_dir"

    # Check if already in PATH
    local -a _canonical_paths
    _get_canonical_path_array

    [[ "$debug" == "true" ]] && echo "Debug: Checking against ${#_canonical_paths[@]} existing PATH entries" >&2

    if (( ${_canonical_paths[(Ie)$canonical_dir]} )); then
        [[ "$debug" == "true" ]] && echo "Debug: Found duplicate at canonical path: $canonical_dir" >&2
        return 2  # Special return code for "already exists"
    fi

    [[ "$debug" == "true" ]] && echo "Debug: Validation successful" >&2

    return 0
}

# Add directory to beginning of PATH (higher priority)
# Usage: add_to_path [-d|--debug] <directory_path>
add_to_path() {
    local debug="false"
    local target_dir

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--debug)
                debug="true"
                shift
                ;;
            *)
                target_dir="$1"
                shift
                ;;
        esac
    done

    [[ "$debug" == "true" ]] && echo "Debug: add_to_path called with: $target_dir" >&2

    local validation_result
    _validate_and_normalize_path "$target_dir" "Usage: add_to_path [-d|--debug] <directory_path>" "$debug"
    validation_result=$?

    # Handle validation results
    case $validation_result in
        1) return 1 ;;  # Error occurred
        2)              # Already in PATH: record for replay, no change
            _path_adds+=("$_validated_expanded_dir")
            return 0
            ;;
        0)              # Success: record for replay, then prepend
            _path_adds+=("$_validated_expanded_dir")
            ;;
    esac

    [[ "$debug" == "true" ]] && echo "Debug: Prepending to PATH: $_validated_expanded_dir" >&2

    # Add to PATH (prepend)
    export PATH="$_validated_expanded_dir:$PATH"

    [[ "$debug" == "true" ]] && echo "Debug: PATH updated successfully" >&2

    return 0
}

# Add directory to end of PATH (lower priority)
# Usage: add_to_path_end [-d|--debug] <directory_path>
add_to_path_end() {
    local debug="false"
    local target_dir

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--debug)
                debug="true"
                shift
                ;;
            *)
                target_dir="$1"
                shift
                ;;
        esac
    done

    [[ "$debug" == "true" ]] && echo "Debug: add_to_path_end called with: $target_dir" >&2

    local validation_result
    _validate_and_normalize_path "$target_dir" "Usage: add_to_path_end [-d|--debug] <directory_path>" "$debug"
    validation_result=$?

    # Handle validation results
    case $validation_result in
        1) return 1 ;;  # Error occurred
        2)              # Already in PATH: record for replay, no change
            _path_end_adds+=("$_validated_expanded_dir")
            return 0
            ;;
        0)              # Success: record for replay, then append
            _path_end_adds+=("$_validated_expanded_dir")
            ;;
    esac

    [[ "$debug" == "true" ]] && echo "Debug: Appending to PATH: $_validated_expanded_dir" >&2

    # Add to PATH (append)
    export PATH="$PATH:$_validated_expanded_dir"

    [[ "$debug" == "true" ]] && echo "Debug: PATH updated successfully" >&2

    return 0
}

# Replay every recorded add_to_path/add_to_path_end call, in original
# order, forcing entries to their intended position even when they are
# already in PATH. Called from $ZDOTDIR/.zprofile, which runs after
# macOS path_helper (/etc/zprofile) has demoted our .zshenv additions
# behind the system directories. Replaying prepends in call order
# reproduces exactly the ordering .zshenv originally built.
# Usage: replay_path_adds
replay_path_adds() {
    local d
    for d in "${_path_adds[@]}"; do
        [[ -d "$d" ]] || continue
        path=("$d" "${(@)path:#$d}")
    done
    for d in "${_path_end_adds[@]}"; do
        [[ -d "$d" ]] || continue
        path=("${(@)path:#$d}" "$d")
    done
    typeset -gU path
}

# Helper function to show current PATH in a readable format
# Usage: show_path [-d|--debug]
show_path() {
    local debug="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--debug)
                debug="true"
                shift
                ;;
            *)
                echo "Usage: show_path [-d|--debug]" >&2
                return 1
                ;;
        esac
    done

    [[ "$debug" == "true" ]] && echo "Debug: show_path called" >&2

    echo "Current PATH entries:"
    local -a path_entries
    IFS=':' read -A path_entries <<< "$PATH"

    [[ "$debug" == "true" ]] && echo "Debug: Found ${#path_entries[@]} PATH entries" >&2

    local i=1
    for entry in "${path_entries[@]}"; do
        printf "%2d. %s" "$i" "$entry"
        if [[ ! -d "$entry" ]]; then
            printf " (missing)"
            [[ "$debug" == "true" ]] && echo -n " [DEBUG: Directory does not exist]" >&2
        elif [[ "$debug" == "true" ]]; then
            local canonical_entry
            canonical_entry=$(_get_canonical_path "$entry" 2>/dev/null)
            if [[ -n "$canonical_entry" && "$canonical_entry" != "$entry" ]]; then
                printf " [DEBUG: canonical=%s]" "$canonical_entry"
            fi
        fi
        printf "\n"
        ((i++))
    done
}
