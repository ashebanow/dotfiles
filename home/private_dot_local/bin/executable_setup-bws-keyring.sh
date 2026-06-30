#!/usr/bin/env bash
set -euo pipefail

# setup-bws-keyring.sh — store BWS_ACCESS_TOKEN in the OS keyring.
# Interactive only; exits cleanly when stdin is not a TTY.
#
# Usage: setup-bws-keyring.sh [TOKEN]
#   With TOKEN: stores it directly (non-interactive, for scripting).
#   Without: prompts securely (interactive).

if [[ ! -t 0 ]] && [[ -z "${1:-}" ]]; then
  echo "setup-bws-keyring: no TTY and no token argument; nothing to do." >&2
  exit 0
fi

# ── 1. Get the token ──────────────────────────────────────────────

TOKEN="${1:-}"
if [[ -z "$TOKEN" ]]; then
  read -rsp "BWS Access Token: " TOKEN
  echo
fi

if [[ -z "$TOKEN" ]]; then
  echo "Error: empty token" >&2
  exit 1
fi

# ── 2. Quick validation (optional but catches typos) ──────────────

if command -v bws >/dev/null 2>&1; then
  echo -n "Validating token… "
  if BWS_ACCESS_TOKEN="$TOKEN" bws secret list >/dev/null 2>&1; then
    echo "OK"
  else
    echo "FAILED"
    echo "Warning: token validation failed — storing anyway." >&2
  fi
fi

# ── 3. Store in keyring ───────────────────────────────────────────

if [[ "$OSTYPE" == "darwin"* ]]; then
  security delete-generic-password -a "$USER" -s "bws_access_token" 2>/dev/null || true
  security add-generic-password -a "$USER" -s "bws_access_token" -w "$TOKEN" -A
  echo "✅ Stored in macOS Keychain (pre-authorized for background access)."

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  if ! command -v secret-tool >/dev/null 2>&1; then
    echo "Installing libsecret (provides secret-tool)…"
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get install -y libsecret-tools
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y libsecret
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -S --needed --noconfirm libsecret
    fi
  fi
  echo -n "$TOKEN" | secret-tool store --label="BWS Access Token" bws token
  echo "✅ Stored in GNOME Keyring / Secret Service."

else
  echo "Error: unsupported OS $OSTYPE" >&2
  exit 1
fi

# ── 4. Export for current shell ──────────────────────────────────

export BWS_ACCESS_TOKEN="$TOKEN"
echo "🚀 BWS_ACCESS_TOKEN exported for this session."
