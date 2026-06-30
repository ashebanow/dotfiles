#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------
# setup-mise.sh — idempotent mise setup and bin/bob migration
# Replaces setup-bin-tool.sh. Called from .zshrc on every
# interactive shell; exits early when nothing needs doing.
# ---------------------------------------------------------------

MISE_PATH="$HOME/.local/bin/mise"
CLEANUP_SENTINEL="$HOME/.local/share/mise/.bin-cleanup-done"

# ── 1. Install mise if missing ──────────────────────────────────

if ! command -v mise >/dev/null 2>&1; then
    echo "==> Installing mise..."
    if command -v brew >/dev/null 2>&1; then
        brew install mise
    else
        curl -fsSL https://mise.run | sh
    fi
fi

# Ensure mise is in PATH for the rest of this script
if [[ -x "$MISE_PATH" ]]; then
    export PATH="$HOME/.local/bin:$PATH"
elif ! command -v mise >/dev/null 2>&1; then
    echo "ERROR: mise failed to install" >&2
    exit 1
fi

# ── 2. Set up global tools (idempotent) ─────────────────────────

# bws alias (bitwarden-secrets-manager provides the 'bws' binary)
mise tool-alias set bws bitwarden-secrets-manager 2>/dev/null || true

# Install and activate globally
mise use -g bitwarden-secrets-manager 2>/dev/null || true
mise use -g neovim 2>/dev/null || true
mise use -g github:caioricciuti/dev-cockpit 2>/dev/null || true
mise use -g github:micahkepe/jsongrep 2>/dev/null || true

# ── 3. Clean up stale bws cache (first-run only) ────────────────

if [[ -x "$(mise which bws 2>/dev/null || echo /nonexistent)" ]]; then
    _bw_cache="$HOME/.cache/env/bw_env.sh"
    if [[ -f "$_bw_cache" ]]; then
        # Check if cache has empty values (stale from before bws existed)
        if grep -q '=""' "$_bw_cache" 2>/dev/null; then
            echo "==> Clearing stale bws cache (will regenerate on next shell)"
            rm -f "$_bw_cache"
        fi
    fi
fi

# ── 4. Migrate from bin/bob (first-run only) ────────────────────

if [[ -f "$CLEANUP_SENTINEL" ]]; then
    exit 0
fi

echo "==> Migrating from bin/bob to mise..."

# Remove bob's non-stable neovim releases (keep stable as fallback)
if [[ -d "$HOME/.local/share/bob" ]]; then
    for dir in "$HOME/.local/share/bob"/nightly-* "$HOME/.local/share/bob"/env "$HOME/.local/share/bob"/used; do
        if [[ -e "$dir" ]]; then
            echo "   Removing $dir"
            rm -rf "$dir"
        fi
    done
    # Remove the nvim-bin symlink (mise provides its own)
    if [[ -d "$HOME/.local/share/bob/nvim-bin" ]]; then
        echo "   Removing $HOME/.local/share/bob/nvim-bin"
        rm -rf "$HOME/.local/share/bob/nvim-bin"
    fi
fi

# Remove bin-managed binaries
for binary in bin bob; do
    if [[ -f "$HOME/.local/bin/$binary" ]]; then
        echo "   Removing ~/.local/bin/$binary"
        rm -f "$HOME/.local/bin/$binary"
    fi
done

# Remove old jg (mise manages it now)
if [[ -f "$HOME/.local/bin/jg" ]]; then
    echo "   Removing ~/.local/bin/jg"
    rm -f "$HOME/.local/bin/jg"
fi

# Remove bob's binary directory
if [[ -d "$HOME/.local/share/bob_bin" ]]; then
    echo "   Removing ~/.local/share/bob_bin"
    rm -rf "$HOME/.local/share/bob_bin"
fi

# Remove old setup-bin-tool.sh
if [[ -f "$HOME/.local/bin/setup-bin-tool.sh" ]]; then
    echo "   Removing ~/.local/bin/setup-bin-tool.sh"
    rm -f "$HOME/.local/bin/setup-bin-tool.sh"
fi

# Mark cleanup as done
mkdir -p "$(dirname "$CLEANUP_SENTINEL")"
touch "$CLEANUP_SENTINEL"
echo "==> Migration complete."
