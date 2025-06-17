#!/usr/bin/env bash

source "${DOTFILES}/lib/install/install_common.sh"

# Check dependencies
if ! command -v jq &>/dev/null; then
    log_error "jq is required but not installed. Please install jq first."
    exit 1
fi

APTFILE="$DOTFILES/Aptfile"
APTFILE_NEW="$DOTFILES/Aptfile.new"
declare -A mappings

# Function to set up global mappings table
setup_mappings_table() {
    # Add mappings where Arch/AUR package names differ from Ubuntu package names
    mappings["python-pip"]="python3-pip"
    mappings["python-virtualenv"]="python3-venv"
    mappings["chromium"]="chromium-browser"
    mappings["docker"]="docker.io"
    mappings["python-requests"]="python3-requests"
    mappings["python-numpy"]="python3-numpy"
    mappings["python-matplotlib"]="python3-matplotlib"
    mappings["python-gobject"]="python3-gobject"
    mappings["python-pyquery"]="python3-pyquery"
    mappings["python-screeninfo"]="python3-screeninfo"
    mappings["ttf-dejavu"]="fonts-dejavu"
    mappings["ttf-droid"]="fonts-droid-fallback"
    mappings["noto-fonts"]="fonts-noto"
    mappings["noto-fonts-cjk"]="fonts-noto-cjk"
    mappings["noto-fonts-emoji"]="fonts-noto-color-emoji"
    mappings["noto-fonts-extra"]="fonts-noto-extra"
    mappings["otf-font-awesome"]="fonts-font-awesome"
    mappings["ttf-fira-code"]="fonts-firacode"
    mappings["ttf-fira-sans"]="fonts-fira"
    mappings["ttf-jetbrains-mono"]="fonts-jetbrains-mono"
    mappings["adobe-source-code-pro-fonts"]="fonts-adobe-source-code-pro"
}

# Function to get package name mappings from Arch/AUR to Ubuntu
find_ubuntu_package_matching() {
    local arch_pkg="$1"

    # If mapping exists, return Ubuntu package name, otherwise return original
    if [[ -n "${mappings[$arch_pkg]:-}" ]]; then
        echo "${mappings[$arch_pkg]}"
    else
        echo "$arch_pkg"
    fi
}

# Function to get Arch package metadata
get_arch_metadata() {
    local pkg="$1"

    # Validate input
    [[ -z "$pkg" ]] && return 1

    # Try AUR API first with rate limiting
    sleep 0.1
    local aur_response
    aur_response=$(curl -s --max-time 5 "https://aur.archlinux.org/rpc/?v=5&type=info&arg=${pkg}" 2>/dev/null)

    if [[ -n "$aur_response" ]] && echo "$aur_response" | jq -e '.results[0]' &>/dev/null; then
        echo "$aur_response" | jq -r '.results[0] | {
            Name: .Name,
            Homepage: (.URL // ""),
            Source: (.URLPath // ""),
            Maintainer: (.Maintainer // ""),
            Version: (.Version // ""),
            Description: (.Description // "")
        }' 2>/dev/null
        return 0
    fi

    # Fallback to safe JSON construction
    jq -n --arg name "$pkg" '{
        Name: $name,
        Homepage: "",
        Source: "",
        Maintainer: "",
        Version: "",
        Description: ""
    }'
}

# Function to get Ubuntu package metadata
get_ubuntu_metadata() {
    local pkg="$1"

    # Validate input
    [[ -z "$pkg" ]] && return 1

    # Call apt-cache show once and cache the result
    local apt_info
    apt_info=$(apt-cache show "$pkg" 2>/dev/null)

    # Early return if package not found
    if [[ -z "$apt_info" ]]; then
        jq -n --arg name "$pkg" '{
            Name: $name,
            Homepage: "",
            Source: "",
            Maintainer: "",
            Version: "",
            Description: ""
        }'
        return 0
    fi

    # Extract fields from cached apt_info
    local homepage maintainer version description
    homepage=$(echo "$apt_info" | grep -i "^Homepage:" | cut -d' ' -f2- | head -1)
    version=$(echo "$apt_info" | grep -i "^Version:" | cut -d' ' -f2 | head -1)
    maintainer=$(echo "$apt_info" | grep -i "^Maintainer:" | cut -d' ' -f2- | head -1)
    description=$(echo "$apt_info" | grep -i "^Description:" | cut -d' ' -f2- | head -1)

    # Use consistent field names matching apt-cache show format
    jq -n --arg name "$pkg" \
        --arg Homepage "${homepage:-}" \
        --arg Maintainer "${maintainer:-}" \
        --arg Version "${version:-}" \
        --arg Description "${description:-}" \
        '{
            Name: $name,
            Homepage: $Homepage,
            Source: "",
            Maintainer: $Maintainer,
            Version: $Version,
            Description: $Description
          }'
}

# Function to calculate metadata similarity score
calculate_similarity() {
    local arch_meta="$1"
    local ubuntu_meta="$2"
    local score=0

    # Validate JSON input
    if ! echo "$arch_meta" | jq empty 2>/dev/null; then
        echo "0"
        return 1
    fi
    if ! echo "$ubuntu_meta" | jq empty 2>/dev/null; then
        echo "0"
        return 1
    fi

    # Homepage URL match (high weight)
    local arch_homepage ubuntu_homepage
    arch_homepage=$(echo "$arch_meta" | jq -r '.Homepage // ""')
    ubuntu_homepage=$(echo "$ubuntu_meta" | jq -r '.Homepage // ""')
    if [[ -n "$arch_homepage" && -n "$ubuntu_homepage" && "$arch_homepage" == "$ubuntu_homepage" ]]; then
        score=$((score + 50))
    fi

    # Source repo URL match (high weight)
    local arch_source ubuntu_source
    arch_source=$(echo "$arch_meta" | jq -r '.Source // ""')
    ubuntu_source=$(echo "$ubuntu_meta" | jq -r '.Source // ""')
    if [[ -n "$arch_source" && -n "$ubuntu_source" && "$arch_source" == "$ubuntu_source" ]]; then
        score=$((score + 40))
    fi

    # Maintainer similarity (medium weight)
    local arch_maintainer ubuntu_maintainer
    arch_maintainer=$(echo "$arch_meta" | jq -r '.Maintainer // ""')
    ubuntu_maintainer=$(echo "$ubuntu_meta" | jq -r '.Maintainer // ""')
    if [[ -n "$arch_maintainer" && -n "$ubuntu_maintainer" && "$arch_maintainer" == "$ubuntu_maintainer" ]]; then
        score=$((score + 20))
    fi

    echo "$score"
}

# Main matching function with optimization
find_ubuntu_equivalent_by_metadata() {
    local arch_pkg="$1"

    # Validate input
    [[ -z "$arch_pkg" ]] && return 1

    # OPTIMIZATION: Check exact name match first
    if apt-cache show "$arch_pkg" &>/dev/null; then
        log_debug "Exact name match found: $arch_pkg"
        echo "$arch_pkg"
        return 0
    fi

    # If no exact match, proceed with metadata comparison
    log_debug "No exact match for $arch_pkg, trying metadata comparison..."

    local arch_metadata best_match="" best_score=0
    arch_metadata=$(get_arch_metadata "$arch_pkg")
    [[ $? -ne 0 ]] && return 1

    # Get potential Ubuntu candidates using search (reversed for relevance)
    local candidates_raw
    candidates_raw=$(apt-cache search "$arch_pkg" 2>/dev/null | cut -d' ' -f1)

    # Common patterns as candidates
    local pattern_candidates=(
        "${arch_pkg/python-/python3-}"
        "${arch_pkg/ttf-/fonts-}"
        "${arch_pkg/otf-/fonts-}"
        "${arch_pkg/-git/}"
        "${arch_pkg}-dev"
        "lib${arch_pkg}"
        "${arch_pkg}-bin"
    )

    # Combine all candidates and deduplicate while preserving order
    declare -A seen_candidates
    local candidates=()

    # First, add pattern candidates (highest priority)
    for candidate in "${pattern_candidates[@]}"; do
        # if [[ -n "$candidate" && -z "${seen_candidates[$candidate]}" ]]; then
        if [[ -v "seen_candidates[$candidate]" ]]; then
            log_debug "pattern matching candidate found for $candidate"
            seen_candidates["$candidate"]=1
            candidates+=("$candidate")
        fi
    done

    # Then add search results in reverse order (most relevant first)
    while IFS= read -r candidate; do
        if [[ -n "$candidate" && -z "${seen_candidates[$candidate]}" ]]; then
            seen_candidates["$candidate"]=1
            candidates+=("$candidate")
        fi
    done < <(echo "$candidates_raw" | tac)

    # Process candidates in order of priority
    for candidate in "${candidates[@]:0:10}"; do
        if [[ -n "$candidate" && "$candidate" != "$arch_pkg" ]] && apt-cache show "$candidate" &>/dev/null; then
            local ubuntu_metadata score
            ubuntu_metadata=$(get_ubuntu_metadata "$candidate")
            score=$(calculate_similarity "$arch_metadata" "$ubuntu_metadata")

            log_debug "Candidate $candidate scored $score for $arch_pkg"

            if [[ $score -gt $best_score ]]; then
                best_score=$score
                best_match=$candidate
            fi

            # Early exit for very high confidence matches
            if [[ $score -ge 70 ]]; then
                log_info "Very high confidence match found early: $arch_pkg -> $candidate (score: $score)"
                echo "$candidate"
                return 0
            fi
        fi
    done

    # Only return match if confidence is high enough
    if [[ $best_score -ge 40 ]]; then
        log_info "High confidence match: $arch_pkg -> $best_match (score: $best_score)"
        echo "$best_match"
    else
        log_info "No confident match found for $arch_pkg (best score: $best_score)"
        return 1
    fi
}

# Always create an empty file
>"$APTFILE_NEW"

# do our one time setup of mappings table
setup_mappings_table

# Read arch packages into array
readarray -t arch_package_list <"$DOTFILES/Archfile"

log_info "Processing ${#arch_package_list[@]} packages..."

for pkg in "${arch_package_list[@]}"; do
    # Skip empty lines
    [[ -z "$pkg" ]] && continue

    # Try manual mapping first (fastest)
    ubuntu_pkg=$(find_ubuntu_package_matching "$pkg")

    # If no manual mapping exists, try metadata matching
    if [[ "$ubuntu_pkg" == "$pkg" ]]; then
        metadata_match=$(find_ubuntu_equivalent_by_metadata "$pkg")
        if [ $? -eq 0 ] && [[ -n "$metadata_match" ]]; then
            ubuntu_pkg="$metadata_match"
        fi
    fi

    # Check if package is already installed
    if dpkg -l "$ubuntu_pkg" &>/dev/null; then
        log_debug "Package $pkg ($ubuntu_pkg) is already installed, skipping."
        continue
    fi

    # Package is not installed, check if it's available in apt repos
    if [[ -n "$ubuntu_pkg" ]] && apt-cache show "$ubuntu_pkg" &>/dev/null; then
        log_debug "Package $pkg ($ubuntu_pkg) is available in apt repos, adding to $APTFILE_NEW"
        echo "$ubuntu_pkg" >>"$APTFILE_NEW"
    else
        log_debug "Package $pkg could not be matched or is not available in apt repos."
    fi
done

log_info "Processing complete. Results written to $APTFILE_NEW"
log_info "Be sure to review the file and delete any packages that don't make "
log_info "sense to install on Ubuntu. "
log_info ""
log_info "Once the file is edited, use $(mv -f \"$APTFILE_NEW\" \"$APTFILE\")"
