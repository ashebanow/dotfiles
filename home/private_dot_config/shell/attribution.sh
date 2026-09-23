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

  # The manifest is repo-local. NIX_CONFIG_DIR is exported by core.sh, which
  # sources it before this file and resolves it with ~/.local/bin/nix-config-dir
  # — the one list of where a checkout may live. SECRETSPEC_FILE still overrides,
  # for running against a different tree deliberately.
  local manifest="${SECRETSPEC_FILE:-${NIX_CONFIG_DIR:+$NIX_CONFIG_DIR/secretspec.toml}}"

  # No manifest, or no secretspec, means the tool would launch unattributed.
  # That is a silent loss of attribution rather than a failure, so the tool is
  # still run -- but say so, rather than letting it rot invisibly.
  if [[ ! -f "$manifest" ]] || ! command -v secretspec >/dev/null 2>&1; then
    printf '%s\n' "$tool: attribution disabled — no manifest at ${manifest:-<NIX_CONFIG_DIR unset>} and/or no secretspec on PATH (BOX-149)" >&2
    command "$tool" "$@"
    return $?
  fi

  # No `command` prefix here, unlike the unattributed branch above: it is a shell
  # builtin, needed there only to stop `$tool` resolving back to this function.
  # secretspec execs argv[0] itself, so passing `command` through asks it to exec
  # a builtin and fails with "Failed to run command".
  SECRETSPEC_FILE="$manifest" secretspec run -P production -S bifrost -- "$tool" "$@"
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
