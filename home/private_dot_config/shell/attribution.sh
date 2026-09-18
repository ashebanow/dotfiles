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
# The `--` is load-bearing: without it, an option-shaped argument to the tool
# would be parsed by secretspec instead.
#
# _gateway_client <tool> — shared body for the CLI clients on the gateway.
# Resolves the manifest, then runs the tool under the bifrost scope so the
# virtual key lands in the child's environment and nowhere else.
_gateway_client() {
  local tool="$1"
  shift

  local manifest="${SECRETSPEC_FILE:-}"
  # The manifest is repo-local; resolve it from the known checkouts rather than
  # assuming a cwd. Every host that runs these clients keeps one of them.
  if [[ -z "$manifest" ]]; then
    local candidate
    for candidate in "$HOME/Development/nix/nix-config/main/secretspec.toml" \
                     "$HOME/nix-config/secretspec.toml"; do
      [[ -f "$candidate" ]] && manifest="$candidate" && break
    done
  fi

  # No manifest, or no secretspec, means the tool would launch unattributed.
  # That is a silent loss of attribution rather than a failure, so the tool is
  # still run -- but say so, rather than letting it rot invisibly.
  if [[ ! -f "$manifest" ]] || ! command -v secretspec >/dev/null 2>&1; then
    printf '%s\n' "$tool: attribution disabled — secretspec or secretspec.toml not found (BOX-149)" >&2
    command "$tool" "$@"
    return $?
  fi

  SECRETSPEC_FILE="$manifest" secretspec run -P production -S bifrost -- command "$tool" "$@"
}

pi() {
  _gateway_client pi "$@"
}

# hermes (BOX-197) via the same mechanism. Its config lives in a chezmoi
# template and could carry a bitwardenSecrets value, but the template renders
# to disk -- so this keeps the key in the process env instead, matching pi and
# giving both clients one mechanism to reason about.
hermes() {
  _gateway_client hermes "$@"
}
