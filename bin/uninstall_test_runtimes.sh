#!/usr/bin/env bash

# Helper script to uninstall simulator runtimes for testing and cleanup purposes

set -eo pipefail

# Source our common functions if available
if [[ -f "${DOTFILES:-$(dirname "$0")}/lib/common/all.sh" ]]; then
    source "${DOTFILES:-$(dirname "$0")}/lib/common/all.sh"
fi

function usage() {
    echo "Usage: $0 [--dry-run] [command|runtime_name...]"
    echo ""
    echo "Commands:"
    echo "  cleanup                         # Interactive cleanup of old runtimes"
    echo "  latest                          # Delete latest versions of each platform"
    echo ""
    echo "Examples:"
    echo "  $0 cleanup                      # Clean up old runtimes interactively"
    echo "  $0 --dry-run cleanup            # Show what cleanup would delete"
    echo "  $0 \"iOS 26.0\"                  # Delete specific runtime"
    echo "  $0 \"iOS 26.0\" \"watchOS 26.0\"   # Delete multiple runtimes"
    echo "  $0 latest                       # Delete latest versions of each platform"
    echo ""
    echo "Available runtimes:"
    xcrun simctl runtime list
}

function delete_runtime() {
    local runtime_name="$1"
    local dry_run_flag="$2"
    
    echo "🗑️  Deleting runtime: $runtime_name"
    if xcrun simctl runtime delete "$runtime_name" $dry_run_flag; then
        echo "✅ Successfully deleted: $runtime_name"
    else
        echo "❌ Failed to delete: $runtime_name"
        return 1
    fi
}

function get_runtime_info() {
    # Parse simctl runtime list output to get structured data
    # Returns: platform version build_number uuid status
    xcrun simctl runtime list | grep -E "^(iOS|watchOS|tvOS|xrOS)" | while read -r line; do
        # Parse line like: "iOS 17.5 (21F79) - 5EB506D0-4429-4D7C-99A9-EFC35B93AFFB (Ready)"
        # Use sed to extract the parts
        local platform=$(echo "$line" | sed -E 's/^([a-zA-Z]+) .*/\1/')
        local version=$(echo "$line" | sed -E 's/^[a-zA-Z]+ ([0-9]+\.[0-9]+) .*/\1/')
        local build=$(echo "$line" | sed -E 's/.*\(([^)]+)\) - .*/\1/')
        local uuid=$(echo "$line" | sed -E 's/.* - ([A-F0-9-]+) .*/\1/')
        local status=$(echo "$line" | sed -E 's/.*\(([^)]+)\)$/\1/')
        
        if [[ -n "$platform" && -n "$version" && -n "$build" && -n "$uuid" && -n "$status" ]]; then
            echo "$platform|$version|$build|$uuid|$status"
        fi
    done
}

function get_current_release_versions() {
    # Get the latest non-beta versions for each platform
    local ios_latest="" watchos_latest="" tvos_latest="" xros_latest=""
    
    while IFS='|' read -r platform version build uuid status; do
        # Skip beta versions (contain letters in build numbers like "21A5277g") 
        if [[ ! "$build" =~ [a-zA-Z] ]]; then
            case "$platform" in
                "iOS")
                    if [[ -z "$ios_latest" ]] || [[ "$version" > "$ios_latest" ]]; then
                        ios_latest="$version"
                    fi
                    ;;
                "watchOS")
                    if [[ -z "$watchos_latest" ]] || [[ "$version" > "$watchos_latest" ]]; then
                        watchos_latest="$version"
                    fi
                    ;;
                "tvOS")
                    if [[ -z "$tvos_latest" ]] || [[ "$version" > "$tvos_latest" ]]; then
                        tvos_latest="$version"
                    fi
                    ;;
                "xrOS")
                    if [[ -z "$xros_latest" ]] || [[ "$version" > "$xros_latest" ]]; then
                        xros_latest="$version"
                    fi
                    ;;
            esac
        fi
    done < <(get_runtime_info)
    
    # Output the results
    [[ -n "$ios_latest" ]] && echo "iOS|$ios_latest"
    [[ -n "$watchos_latest" ]] && echo "watchOS|$watchos_latest"
    [[ -n "$tvos_latest" ]] && echo "tvOS|$tvos_latest"
    [[ -n "$xros_latest" ]] && echo "xrOS|$xros_latest"
}

function find_old_runtimes() {
    local dry_run_flag="$1"
    
    # Get current release versions into local variables
    local ios_current="" watchos_current="" tvos_current="" xros_current=""
    while IFS='|' read -r platform version; do
        case "$platform" in
            "iOS") ios_current="$version" ;;
            "watchOS") watchos_current="$version" ;;
            "tvOS") tvos_current="$version" ;;
            "xrOS") xros_current="$version" ;;
        esac
    done < <(get_current_release_versions)
    
    echo "🔍 Current release versions detected:"
    [[ -n "$ios_current" ]] && echo "  iOS: $ios_current"
    [[ -n "$watchos_current" ]] && echo "  watchOS: $watchos_current"
    [[ -n "$tvos_current" ]] && echo "  tvOS: $tvos_current"
    [[ -n "$xros_current" ]] && echo "  xrOS: $xros_current"
    echo ""
    
    # Find old runtimes
    local old_runtimes=()
    while IFS='|' read -r platform version build uuid status; do
        local current_version=""
        case "$platform" in
            "iOS") current_version="$ios_current" ;;
            "watchOS") current_version="$watchos_current" ;;
            "tvOS") current_version="$tvos_current" ;;
            "xrOS") current_version="$xros_current" ;;
        esac
        
        if [[ -n "$current_version" ]] && [[ "$version" < "$current_version" ]]; then
            old_runtimes+=("$platform $version|$uuid")
            if [[ -n "$dry_run_flag" ]]; then
                echo "Would delete: $platform $version ($build)"
            fi
        fi
    done < <(get_runtime_info)
    
    if [[ ${#old_runtimes[@]} -eq 0 ]]; then
        echo "✅ No old runtimes found to clean up!"
        return 0
    fi
    
    if [[ -n "$dry_run_flag" ]]; then
        echo ""
        echo "📊 Summary: ${#old_runtimes[@]} old runtime(s) would be deleted."
        return 0
    fi
    
    # Interactive cleanup
    echo "Found ${#old_runtimes[@]} old runtime(s) to clean up:"
    for runtime_info in "${old_runtimes[@]}"; do
        local runtime_name="${runtime_info%|*}"
        echo "  🗑️  $runtime_name"
    done
    echo ""
    
    cleanup_old_runtimes_interactive "${old_runtimes[@]}"
}

function cleanup_old_runtimes_interactive() {
    local old_runtimes=("$@")
    local user_choice=""
    local delete_all=false
    
    for runtime_info in "${old_runtimes[@]}"; do
        local runtime_name="${runtime_info%|*}"
        local runtime_uuid="${runtime_info#*|}"
        
        # Skip prompting if user chose "all"
        if [[ "$delete_all" != true ]]; then
            if command -v gum >/dev/null 2>&1; then
                user_choice=$(gum choose --header "Delete runtime: $runtime_name?" "yes" "no" "all" "quit")
            else
                echo "Delete runtime: $runtime_name? (yes/no/all/quit)"
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
                "xcrun simctl runtime delete \"$runtime_uuid\"" \
                "Successfully deleted $runtime_name"
        else
            echo "⏳ Deleting $runtime_name..."
            if xcrun simctl runtime delete "$runtime_uuid"; then
                echo "✅ Successfully deleted: $runtime_name"
            else
                echo "❌ Failed to delete: $runtime_name"
            fi
        fi
    done
    
    echo ""
    echo "🧹 Cleanup completed!"
}

function delete_latest_runtimes() {
    local dry_run_flag="$1"
    
    echo "🔍 Finding latest runtimes to delete..."
    
    # Get the latest runtime for each platform (excluding betas)
    local latest_ios latest_watchos latest_tvos latest_xros
    
    # Parse simctl output to find latest versions
    latest_ios=$(xcrun simctl runtime list | grep "^iOS" | grep -v beta | tail -1 | cut -d'(' -f1 | xargs)
    latest_watchos=$(xcrun simctl runtime list | grep "^watchOS" | grep -v beta | tail -1 | cut -d'(' -f1 | xargs)
    latest_tvos=$(xcrun simctl runtime list | grep "^tvOS" | grep -v beta | tail -1 | cut -d'(' -f1 | xargs)
    latest_xros=$(xcrun simctl runtime list | grep "^xrOS" | grep -v beta | tail -1 | cut -d'(' -f1 | xargs)
    
    # Delete each if found
    [[ -n "$latest_ios" ]] && delete_runtime "$latest_ios" "$dry_run_flag"
    [[ -n "$latest_watchos" ]] && delete_runtime "$latest_watchos" "$dry_run_flag"
    [[ -n "$latest_tvos" ]] && delete_runtime "$latest_tvos" "$dry_run_flag"
    [[ -n "$latest_xros" ]] && delete_runtime "$latest_xros" "$dry_run_flag"
}

# Parse arguments
dry_run_flag=""
runtimes_to_delete=()

for arg in "$@"; do
    case "$arg" in
        --dry-run)
            dry_run_flag="--dry-run"
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        cleanup)
            find_old_runtimes "$dry_run_flag"
            exit $?
            ;;
        latest)
            delete_latest_runtimes "$dry_run_flag"
            exit $?
            ;;
        *)
            runtimes_to_delete+=("$arg")
            ;;
    esac
done

# If no specific runtimes specified, show usage
if [[ ${#runtimes_to_delete[@]} -eq 0 ]]; then
    usage
    exit 0
fi

# Delete specified runtimes
for runtime in "${runtimes_to_delete[@]}"; do
    delete_runtime "$runtime" "$dry_run_flag"
done

echo ""
echo "📋 Current runtimes after deletion:"
xcrun simctl runtime list