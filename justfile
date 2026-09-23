#!/usr/bin/env just --justfile

# Recipes for working on THIS chezmoi dotfiles repo.
#
# `just` uses the nearest justfile found while searching upward, so being
# inside this repo shadows the global ~/.justfile (installed by chezmoi
# from home/dot_justfile.tmpl). Import it so the global recipes (chezmoi
# update-config, pi-update, nix-config clean/dry-run/switch/build-hm/...)
# stay visible and runnable here too. Recipes defined in THIS file are the
# chezmoi-repo-specific ones; note `build` (chezmoi apply) is the same
# operation as the imported update-config.

import "~/.justfile"

# Build the dotfiles: apply this repo's managed files to the current
# machine (chezmoi apply). Same as update-config, kept under the name you
# reach for when developing this repo.
[group('chezmoi')]
build:
    chezmoi apply

# For testing, make chezmoi forget about script run state
[group('chezmoi')]
clear-chezmoi-script-state:
    chezmoi state delete-bucket --bucket=scriptState

# Re-vendor the Matt Pocock skill set into home/dot_agents/skills from
# mattpocock/skills, refresh the claude/pi symlink trees, and deploy.
#
# The installer has no destination flag (see the script's header for the
# proof), so it cannot write into the chezmoi source directly; the script runs
# it in a throwaway sandbox and copies the result in. Repo-local entries in
# that directory (README.md, linear-cli, afk-loop) are preserved.
#
# Defaults to a dry run; pass `apply` to actually do it. Upstream changes
# arrive as ordinary git diffs -- review them before committing.
[group('agents')]
agents-skills-sync action="dry-run":
    #!/usr/bin/env bash
    set -euo pipefail
    script="home/private_dot_local/bin/executable_agents-skills-sync"
    case "{{action}}" in
      dry-run) "$script" --dry-run ;;
      stage)   "$script" --no-apply ;;
      apply)   "$script" ;;
      *) echo "usage: just agents-skills-sync [dry-run|stage|apply]" >&2; exit 2 ;;
    esac

# Re-vendor the linear-cli agent skill from an upstream release tag into
# home/dot_agents/skills/linear-cli (deployed to ~/.agents/skills/linear-cli,
# which pi scans natively; ~/.claude/skills symlinks to it). The skill must
# match the binary nix-config installs — `just linear-bump <tag>` over in
# nix-config bumps both; run this alone only to repair the vendored copy.
# Drops upstream's SKILL.template.md and scripts/ (doc-generation inputs,
# not skill content) and records the provenance in VENDORED.md.
[group('agents')]
linear-vendor-skill tag:
    #!/usr/bin/env bash
    set -euo pipefail
    tag="{{tag}}"; ver="${tag#v}"
    dest="home/dot_agents/skills/linear-cli"
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    curl -sSfL "https://github.com/schpet/linear-cli/archive/refs/tags/v${ver}.tar.gz" | tar xz -C "$tmp"
    src="$tmp/linear-cli-${ver}/skills/linear-cli"
    [[ -f "$src/SKILL.md" ]] || { echo "no skills/linear-cli/SKILL.md in v${ver}" >&2; exit 1; }
    rm -rf "$dest"; mkdir -p "$dest"
    cp "$src/SKILL.md" "$dest/"
    cp -R "$src/references" "$dest/references"
    {
      echo "# Vendored from schpet/linear-cli"
      echo
      echo "- Tag: v${ver}"
      echo "- Source path: skills/linear-cli (SKILL.md + references/; SKILL.template.md and scripts/ dropped)"
      echo "- Vendored: $(date +%Y-%m-%d) via \`just linear-vendor-skill v${ver}\`"
      echo
      echo "Must match the linear-cli version pinned in nix-config's lib/overlays/linear-cli.nix."
      echo "Do not edit by hand; re-run the recipe."
    } > "$dest/VENDORED.md"
    echo "vendored linear-cli skill v${ver} -> $dest"

# ===== SECRET HYGIENE =====

# Refuse to commit a credential into this repo (BOX-212).
#
# The tree is managed, not secret-free: home/dot_pi/agent/private_auth.json is
# tracked so chezmoi creates a 0600 placeholder at ~/.pi/agent/auth.json on a
# fresh machine. The `private_` prefix sets *permissions*; it does nothing to
# keep content out of git, and .gitignore does not cover that path. pi writes
# real credentials into the live file on `/login`, so a `chezmoi add` at the
# wrong moment would copy a key into a tracked file. Real secrets belong in
# BWS, resolved at launch by `secretspec run` (see attribution.sh).
#
# Default checks the staged index — the content about to become a commit.
[group('secrets')]
secrets-guard:
    @home/private_dot_local/bin/executable_secrets-guard

# Same check over every tracked file, not just the index. For a periodic audit
# or CI.
[group('secrets')]
secrets-guard-all:
    @home/private_dot_local/bin/executable_secrets-guard --all
