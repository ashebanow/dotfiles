# ~/.config/shell/attribution.sh — per-client gateway attribution (BOX-149)
# Sourced by .bashrc and .zshrc on every machine class, after core.sh.
#
# The bifrost gateway records a per-client virtual key (`x-bf-vk`) on every log
# row as `virtual_key_name`, so its log view can attribute and filter requests
# by originating client. Each client's key is a real secret: randomly generated
# and held in BWS. Nothing here or anywhere in git holds a value.
#
# Why a shell function and not a wrapper on PATH:
#   `pi` is installed by nvm, whose bin dir is *prepended* late in .zshrc —
#   after ~/.local/bin — so a wrapper script in ~/.local/bin does not win the
#   PATH lookup. A shell function does, in both shells, regardless of ordering.
#
# Why `secretspec run` and not a shell export:
#   secrets.sh is interactive-only, so an `export VK_PI=…` there silently
#   no-ops for a non-interactive `pi` launch and the request would go out
#   unattributed. `secretspec run` resolves the value at launch from the same
#   BWS item the gateway reads, so the two sides cannot drift. The value lives
#   only in the child process env; it is never written to disk.
#
# The `--` is load-bearing: without it, an option-shaped argument to pi would
# be parsed by secretspec instead.
pi() {
  local manifest="${SECRETSPEC_FILE:-}"
  # The manifest is repo-local; resolve it from the known checkout rather than
  # assuming a cwd. Both hosts that run pi keep the nix-config checkout here.
  if [[ -z "$manifest" ]]; then
    for candidate in "$HOME/Development/nix/nix-config/main/secretspec.toml" \
                     "$HOME/nix-config/secretspec.toml"; do
      [[ -f "$candidate" ]] && manifest="$candidate" && break
    done
  fi

  # No manifest, or no secretspec, means pi would launch unattributed. That is
  # a silent loss of attribution, not a failure — but say so, once, rather than
  # letting it rot invisibly.
  if [[ ! -f "$manifest" ]] || ! command -v secretspec >/dev/null 2>&1; then
    printf '%s\n' "pi: attribution disabled — secretspec or secretspec.toml not found (BOX-149)" >&2
    command pi "$@"
    return $?
  fi

  SECRETSPEC_FILE="$manifest" secretspec run -P production -S bifrost -- command pi "$@"
}
