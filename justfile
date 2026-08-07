#!/usr/bin/env just --justfile

# Path to the nix-config flake (lumquat) that manages this machine's
# packages, if it's a known host. Override with NIX_CONFIG_DIR.
nix_config_dir := env_var_or_default("NIX_CONFIG_DIR", env_var("HOME") + "/Development/nix/nix-config/lumquat")

# Default recipe to show available commands
default:
    @just --list

# ===== TESTING =====

# Run install script tests (if they exist)
[group('testing')]
test-install:
    @./lib/testing/run_install_tests.sh

# ===== NIX =====

# Fail fast if this machine isn't a known host in the nix-config flake
[group('nix')]
[private]
_nix-host:
    #!/usr/bin/env bash
    set -euo pipefail
    # hostname -s reads the actual configured HostName. scutil --get
    # LocalHostName is deliberately not used — it's the Bonjour/mDNS
    # name and often just the factory "MacBook-Pro" default even when
    # HostName has been customized.
    host="$(hostname -s)"
    if [[ ! -d "{{nix_config_dir}}/hosts/$host" ]]; then
        echo "error: no hosts/$host under {{nix_config_dir}} — this machine isn't a known nix-config host" >&2
        exit 1
    fi

# Validate the nix-config flake (nix flake check)
[group('nix')]
nix-flake-check: _nix-host
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{nix_config_dir}}"
    nix flake check

# Preview what darwin-rebuild switch would change, without applying it
[group('nix')]
nix-dry-run: _nix-host
    #!/usr/bin/env bash
    set -euo pipefail
    host="$(hostname -s)"
    cd "{{nix_config_dir}}"
    if command -v darwin-rebuild >/dev/null 2>&1; then
        darwin-rebuild switch --flake ".#${host}" --dry-run
    else
        nix run nix-darwin -- switch --flake ".#${host}" --dry-run
    fi

# Apply the nix-config flake for real (darwin-rebuild switch)
[group('nix')]
nix-switch: _nix-host
    #!/usr/bin/env bash
    set -euo pipefail
    host="$(hostname -s)"
    cd "{{nix_config_dir}}"
    if command -v darwin-rebuild >/dev/null 2>&1; then
        darwin-rebuild switch --flake ".#${host}"
    else
        nix run nix-darwin -- switch --flake ".#${host}"
    fi

# Install declared-but-missing Mac App Store apps (install-only, never
# uninstalls). Defaults to --dry-run; pass --execute to actually install:
#   just nix-mas-sync -- --execute
[group('nix')]
nix-mas-sync *args: _nix-host
    #!/usr/bin/env bash
    set -euo pipefail
    host="$(hostname -s)"
    "{{nix_config_dir}}/scripts/darwin-migration/mas-sync.sh" "$host" {{args}}
