#!/bin/bash
# Package update checker - manually check if package files need updating

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}📦 Package Update Checker${NC}"
    echo "=========================="
    echo ""
}

check_package_files_status() {
    local mappings_file="$DOTFILES_DIR/packages/package_mappings.toml"
    local any_outdated=false
    
    if [[ ! -f "$mappings_file" ]]; then
        echo -e "${RED}❌ package_mappings.toml not found${NC}"
        return 1
    fi
    
    local mappings_time=$(stat -f %m "$mappings_file" 2>/dev/null || stat -c %Y "$mappings_file" 2>/dev/null)
    
    echo "📋 Checking package file status..."
    echo ""
    
    # Check each potential package file
    for pkg_file in Brewfile Archfile Aptfile Flatfile; do
        local full_path="$DOTFILES_DIR/packages/$pkg_file"
        if [[ -f "$full_path" ]]; then
            local file_time=$(stat -f %m "$full_path" 2>/dev/null || stat -c %Y "$full_path" 2>/dev/null)
            local package_count=$(grep -c '^[^#]' "$full_path" 2>/dev/null || echo "0")
            
            if [[ $file_time -lt $mappings_time ]]; then
                echo -e "   ${YELLOW}⚠️  $pkg_file${NC} - outdated ($package_count packages)"
                any_outdated=true
            else
                echo -e "   ${GREEN}✅ $pkg_file${NC} - up to date ($package_count packages)"
            fi
        else
            echo -e "   ${BLUE}ℹ️  $pkg_file${NC} - not generated for this platform"
        fi
    done
    
    echo ""
    
    if $any_outdated; then
        echo -e "${YELLOW}⚡ Some package files are outdated and should be regenerated${NC}"
        return 1
    else
        echo -e "${GREEN}✅ All package files are up to date${NC}"
        return 0
    fi
}

show_cache_status() {
    local cache_file="$DOTFILES_DIR/packages/.repology_cache.json"
    
    echo "🗄️  Checking cache status..."
    echo ""
    
    if [[ -f "$cache_file" ]]; then
        local cache_size=$(du -h "$cache_file" | cut -f1)
        local entry_count=$(jq 'keys | length' "$cache_file" 2>/dev/null || echo "unknown")
        local cache_age_days=$((( $(date +%s) - $(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null) ) / 86400))
        
        echo "   📊 Cache size: $cache_size"
        echo "   📦 Cached packages: $entry_count"
        echo "   🕒 Last updated: $cache_age_days days ago"
        
        if [[ $cache_age_days -gt 7 ]]; then
            echo -e "   ${YELLOW}⚠️  Cache is getting old (>7 days)${NC}"
        else
            echo -e "   ${GREEN}✅ Cache is fresh${NC}"
        fi
    else
        echo -e "   ${RED}❌ No cache file found${NC}"
        echo "   Run 'just regen-toml' to create initial cache"
    fi
    
    echo ""
}

suggest_actions() {
    echo "🔧 Available actions:"
    echo ""
    echo "   just generate-package-lists    - Regenerate package files"
    echo "   just regen-toml                - Regenerate package_mappings.toml"  
    echo "   just regen-and-generate        - Do both (full refresh)"
    echo "   just cache-stats               - View detailed cache statistics"
    echo "   ./install.sh                   - Install packages (idempotent)"
    echo ""
    echo "💡 Note: chezmoi apply will automatically regenerate and install"
    echo "   packages when package_mappings.toml or install scripts change"
    echo ""
}

main() {
    print_header
    
    # Check if we're in the right directory
    if [[ ! -f "$DOTFILES_DIR/justfile" ]]; then
        echo -e "${RED}❌ Error: Not in dotfiles directory or justfile not found${NC}"
        exit 1
    fi
    
    show_cache_status
    
    if ! check_package_files_status; then
        echo ""
        echo -e "${YELLOW}🔄 Recommendation: Run 'just generate-package-lists' to update package files${NC}"
        echo ""
        suggest_actions
        exit 1
    else
        echo ""
        suggest_actions
        exit 0
    fi
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo ""
        echo "Check if package files need to be regenerated based on package_mappings.toml changes."
        echo ""
        echo "Exit codes:"
        echo "  0 - All files up to date"
        echo "  1 - Some files need regeneration"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac