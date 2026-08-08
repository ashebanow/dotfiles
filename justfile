#!/usr/bin/env just --justfile

# Path to the nix-config flake (lumquat) that manages this machine's
# packages, if it's a known host. Override with NIX_CONFIG_DIR.
nix_config_dir := env_var_or_default("NIX_CONFIG_DIR", env_var("HOME") + "/Development/nix/nix-config/lumquat")

# Default recipe to show available commands
default:
    @just --list

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

# Preview what darwin-rebuild switch would change, without applying it.
# Uses `darwin-rebuild build` rather than `switch --dry-run` — the
# latter is broken under Determinate Nix (and upstream nix in general):
# it refuses to plan the final darwin-system-* derivation because no
# substituter has ever pre-built that exact config combination, even
# though a real local build works fine. See NixOS/nix#13411. `build`
# does a real local build into ./result without activating/switching,
# so it needs no sudo — only nix-switch does. Once built, diffs
# against /run/current-system (the active generation) to show what
# would actually change. On a machine that's never had a successful
# switch, /run/current-system doesn't exist yet — nix-darwin creates
# it during activation — so there's no "before" to diff against; in
# that case this lists what's declared instead.
[group('nix')]
nix-dry-run: _nix-host
    #!/usr/bin/env bash
    set -euo pipefail
    host="$(hostname -s)"
    cd "{{nix_config_dir}}"
    if command -v nh >/dev/null 2>&1; then
        nh darwin build ".#${host}"
    elif command -v darwin-rebuild >/dev/null 2>&1; then
        sudo darwin-rebuild build --flake ".#${host}"
    else
        nix run nix-darwin -- build --flake ".#${host}"
    fi
    echo
    if [[ -e /run/current-system ]]; then
        echo "=== Changes vs. the currently active generation ==="
        nix store diff-closures /run/current-system ./result
    else
        echo "=== No previous generation to diff against (first-ever switch on this machine) ==="
        echo "Declared home.packages:"
        nix eval --json ".#darwinConfigurations.${host}.config.home-manager.users.ashebanow.home.packages" \
            --apply 'pkgs: map (p: p.pname or p.name) pkgs' | jq -r '.[]' | sort | sed 's/^/  - /'
        echo "Declared Homebrew brews:"
        nix eval --json ".#darwinConfigurations.${host}.config.homebrew.brews" | jq -r '.[].name' | sed 's/^/  - /'
        echo "Declared Homebrew casks:"
        nix eval --json ".#darwinConfigurations.${host}.config.homebrew.casks" | jq -r '.[].name' | sed 's/^/  - /'
    fi

# Apply the nix-config flake for real (darwin-rebuild switch)
[group('nix')]
nix-switch: _nix-host
    #!/usr/bin/env bash
    set -euo pipefail
    host="$(hostname -s)"
    cd "{{nix_config_dir}}"
    if command -v nh >/dev/null 2>&1; then
        nh darwin switch ".#${host}"
    elif command -v darwin-rebuild >/dev/null 2>&1; then
        sudo darwin-rebuild switch --flake ".#${host}"
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
