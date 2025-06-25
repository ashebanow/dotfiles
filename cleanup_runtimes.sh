#!/usr/bin/env bash

# Simple runtime cleanup script

set -eo pipefail

# Source our common functions if available
if [[ -f "${DOTFILES:-$(dirname "$0")}/lib/common/all.sh" ]]; then
    source "${DOTFILES:-$(dirname "$0")}/lib/common/all.sh"
fi

function version_greater() {
    # Compare two semantic version numbers
    # Returns 0 (true) if $1 > $2, 1 (false) otherwise
    local ver1="$1"
    local ver2="$2"
    
    # Split versions into major.minor
    local ver1_major=$(echo "$ver1" | cut -d. -f1)
    local ver1_minor=$(echo "$ver1" | cut -d. -f2)
    local ver2_major=$(echo "$ver2" | cut -d. -f1)
    local ver2_minor=$(echo "$ver2" | cut -d. -f2)
    
    # Compare major version first
    if [[ $ver1_major -gt $ver2_major ]]; then
        return 0
    elif [[ $ver1_major -lt $ver2_major ]]; then
        return 1
    else
        # Major versions equal, compare minor
        if [[ $ver1_minor -gt $ver2_minor ]]; then
            return 0
        else
            return 1
        fi
    fi
}

function usage() {
    echo "Usage: $0 [--dry-run] cleanup"
    echo ""
    echo "This script will:"
    echo "  1. Find the latest stable version for each platform"
    echo "  2. Identify older versions that can be cleaned up"
    echo "  3. Prompt you to delete each old runtime interactively"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deleted without actually deleting"
    echo ""
    echo "Available runtimes:"
    xcrun simctl runtime list
}

function find_and_cleanup_old_runtimes() {
    local dry_run="$1"
    
    echo "🔍 Analyzing installed runtimes..."
    
    # Get all runtimes and find latest stable versions
    local temp_file=$(mktemp)
    xcrun simctl runtime list | grep -E "^(iOS|watchOS|tvOS|xrOS)" > "$temp_file"
    
    # Find latest versions for each platform (including betas, since they might be newest)
    local ios_latest="" watchos_latest="" tvos_latest="" xros_latest=""
    
    while read -r line; do
        local platform=$(echo "$line" | sed -E 's/^([a-zA-Z]+) .*/\1/')
        local version=$(echo "$line" | sed -E 's/^[a-zA-Z]+ ([0-9]+\.[0-9]+) .*/\1/')
        
        case "$platform" in
            "iOS")
                if [[ -z "$ios_latest" ]] || version_greater "$version" "$ios_latest"; then
                    ios_latest="$version"
                fi
                ;;
            "watchOS")
                if [[ -z "$watchos_latest" ]] || version_greater "$version" "$watchos_latest"; then
                    watchos_latest="$version"
                fi
                ;;
            "tvOS")
                if [[ -z "$tvos_latest" ]] || version_greater "$version" "$tvos_latest"; then
                    tvos_latest="$version"
                fi
                ;;
            "xrOS")
                if [[ -z "$xros_latest" ]] || version_greater "$version" "$xros_latest"; then
                    xros_latest="$version"
                fi
                ;;
        esac
    done < "$temp_file"
    
    echo "📋 Latest versions detected:"
    [[ -n "$ios_latest" ]] && echo "  iOS: $ios_latest"
    [[ -n "$watchos_latest" ]] && echo "  watchOS: $watchos_latest"
    [[ -n "$tvos_latest" ]] && echo "  tvOS: $tvos_latest"
    [[ -n "$xros_latest" ]] && echo "  xrOS: $xros_latest"
    echo ""
    
    # Find old runtimes to delete
    local old_runtimes=()
    while read -r line; do
        local platform=$(echo "$line" | sed -E 's/^([a-zA-Z]+) .*/\1/')
        local version=$(echo "$line" | sed -E 's/^[a-zA-Z]+ ([0-9]+\.[0-9]+) .*/\1/')
        local build=$(echo "$line" | sed -E 's/.*\(([^)]+)\) - .*/\1/')
        local uuid=$(echo "$line" | sed -E 's/.* - ([A-F0-9-]+) .*/\1/')
        
        local current_version=""
        case "$platform" in
            "iOS") current_version="$ios_latest" ;;
            "watchOS") current_version="$watchos_latest" ;;
            "tvOS") current_version="$tvos_latest" ;;
            "xrOS") current_version="$xros_latest" ;;
        esac
        
        if [[ -n "$current_version" ]] && ! version_greater "$version" "$current_version" && [[ "$version" != "$current_version" ]]; then
            old_runtimes+=("$platform $version|$uuid|$build")
            if [[ "$dry_run" == "true" ]]; then
                echo "Would delete: $platform $version ($build)"
            fi
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    if [[ ${#old_runtimes[@]} -eq 0 ]]; then
        echo "✅ No old runtimes found to clean up!"
        return 0
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "📊 Summary: ${#old_runtimes[@]} old runtime(s) would be deleted."
        return 0
    fi
    
    # Interactive cleanup
    echo "Found ${#old_runtimes[@]} old runtime(s) to clean up:"
    for runtime_info in "${old_runtimes[@]}"; do
        local runtime_name="${runtime_info%%|*}"
        echo "  🗑️  $runtime_name"
    done
    echo ""
    
    interactive_cleanup "${old_runtimes[@]}"
}

function interactive_cleanup() {
    local old_runtimes=("$@")
    local user_choice=""
    local delete_all=false
    
    for runtime_info in "${old_runtimes[@]}"; do
        IFS='|' read -r runtime_name uuid build <<< "$runtime_info"
        
        # Skip prompting if user chose "all"
        if [[ "$delete_all" != true ]]; then
            if command -v gum >/dev/null 2>&1; then
                user_choice=$(gum choose --header "Delete runtime: $runtime_name ($build)?" "yes" "no" "all" "quit")
            else
                echo "Delete runtime: $runtime_name ($build)? (yes/no/all/quit)"
                read -r user_choice
            fi
            
            case "$user_choice" in
                "quit")
                    echo "🛑 Cleanup cancelled by user"
                    return 0
                    ;;
                "all")
                    delete_all=true
                    ;;
                "no")
                    echo "⏭️  Skipping: $runtime_name"
                    continue
                    ;;
                "yes")
                    # Will delete this one
                    ;;
                *)
                    echo "⏭️  Invalid choice, skipping: $runtime_name"
                    continue
                    ;;
            esac
        fi
        
        # Delete the runtime
        echo "🗑️  Deleting: $runtime_name"
        if command -v gum >/dev/null 2>&1 && declare -f show_spinner >/dev/null 2>&1; then
            show_spinner "Deleting $runtime_name" \
                "xcrun simctl runtime delete \"$uuid\"" \
                "Successfully deleted $runtime_name"
        else
            echo "⏳ Deleting $runtime_name..."
            if xcrun simctl runtime delete "$uuid"; then
                echo "✅ Successfully deleted: $runtime_name"
            else
                echo "❌ Failed to delete: $runtime_name"
            fi
        fi
    done
    
    echo ""
    echo "🧹 Cleanup completed!"
    echo ""
    echo "📋 Remaining runtimes:"
    xcrun simctl runtime list
}

# Main script
dry_run="false"
command=""

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            dry_run="true"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        cleanup)
            command="cleanup"
            ;;
        *)
            echo "Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

if [[ "$command" == "cleanup" ]]; then
    find_and_cleanup_old_runtimes "$dry_run"
else
    usage
    exit 1
fi