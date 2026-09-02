# home-manager ↔ chezmoi integration (apply on switch)

**Ticket:** https://linear.app/boxbow/issue/BOX-127
**Date:** 2026-09-01 (research pass)
**Scope:** How home-manager should install chezmoi for the `podman` user on the
NixOS host `lumquat` and run `chezmoi apply` as part of every `nh os switch`.
Answers four sub-questions: (1) does a `programs.chezmoi` home-manager module
exist and does it auto-apply, (2) is `home.activation` the right hook, (3) how
the source repo stays on disk for periodic apply/update, (4) interaction with
the headless / no-BWS constraints.

## Method

- Home-manager module surface verified against **primary sources**: the full
  recursive git tree of `nix-community/home-manager` master (commit
  `1dc2d1f720ab17fc7981e087346bf54b26d284b1`, 2026-09-01), the GitHub commits
  API for the path `modules/programs/chezmoi.nix`, issue/PR search on the repo,
  the official manual (`nix-community.github.io/home-manager`), and the module
  sources `modules/home-environment.nix`, `modules/lib/types-dag.nix`,
  `nixos/default.nix`.
- chezmoi side verified against `twpayne/chezmoi` master
  (`assets/chezmoi.io/docs/`, 343 doc files) and chezmoi.io.
- Local context read from the read-only second repo
  `/Users/ashebanow/Development/nix/nix-config/main`
  (`modules/infra/nixos-builder.nix`, `modules/infra/hm-infra.nix`,
  `modules/features/cli-tools.nix`, `modules/features/cli-system-tools.nix`,
  `lib/my-options-module.nix`, `hosts/lumquat/configuration.nix`,
  `SECRET_SYNC.md`) and from this repo's templates
  (`home/.chezmoi.toml.tmpl`, `home/.chezmoiignore.tmpl`,
  `home/private_dot_config/git/config.tmpl`, `home/.chezmoiscripts/linux/`).
- Nothing in `/Users/ashebanow/Development/nix/nix-config/main` was modified.

## Findings

### 1. `programs.chezmoi` does NOT exist in home-manager — there is nothing to "activate"

- The full recursive tree of home-manager master (5,475 entries, commit
  `1dc2d1f7`, 2026-09-01) contains **zero** paths with `chezmoi` in them
  (case-insensitive). `modules/programs/` has 413 modules; none is named
  chezmoi. Source: GitHub tree API,
  `github.com/nix-community/home-manager/git/trees/master?recursive=1`.
- The commits API for the path `modules/programs/chezmoi.nix` returns **0
  commits** — the file never existed in home-manager history. Issue/PR search
  for `chezmoi` on the repo returns no PRs and one unrelated issue (#3346, a
  `home.file` collision bug). The official 3rd-party module collections page
  (`3rd-party/collections.html`) has no chezmoi entry.
- chezmoi's own docs have **no** "chezmoi and home-manager" integration page.
  The only home-manager mention in all 343 doc files of `twpayne/chezmoi`
  master is a link to an article titled "migrating from nix and home-manager to
  homebrew and chezmoi" (`docs/links/articles.md.yaml`) — i.e. the migration
  *away* direction, not an integration guide.
- Consequences: the premise "options exist: `enable`, `package`, and a
  `configuration` submodule" is not backed by any primary source; and there is
  consequently **no module that could auto-run `chezmoi apply`** on activation.
  chezmoi must be installed as a plain package and invoked explicitly.

### 2. The real mechanism: `home.activation` (runs on every `nh os switch`)

- `home.activation` is an option of type `lib.hm.types.dagOf types.str`,
  default `{}`, declared in `modules/home-environment.nix` (home-manager
  master). Its description mandates that any block with side effects (writing
  or deleting files) **must** be placed after the special `writeBoundary`
  block, which itself is `lib.hm.dag.entryAnywhere` in the same file.
- Canonical form (from the option's own example in `home-environment.nix`):
  `home.activation.chezmoiApply = lib.hm.dag.entryAfter ["writeBoundary"] "…";`.
  The `lib.hookAfter …` shape in the ticket is not a home-manager API — DAG
  entries use `lib.hm.dag.entryAfter`/`entryBefore`/`entryAnywhere`.
  (`modules/lib/types-dag.nix` shows bare strings are auto-wrapped with
  `entryAnywhere`, which is *before* the write boundary — fine for pure checks,
  wrong for writes.)
- **Activation runs on every system switch.** Home Manager's NixOS module
  (imported via `home-manager.nixosModules.home-manager`, as our
  `nixos-builder.nix` already does) registers a systemd unit
  `home-manager-<user>.service` (`wantedBy = multi-user.target`, `ExecStart`
  runs the user's `…/activate` script as the user; `nixos/default.nix`,
  `!startAsUserService` branch). The official manual
  (`installation/nixos.html`): *"By default, Home Manager activates each
  configured user during boot and system rebuilds through a NixOS system
  service: `systemctl status "home-manager-$USER.service"`"*. The flakes
  manual (`nix-flakes/nixos.html`): the HM configuration "is automatically
  rebuilt with the system when using the appropriate command for the system,
  such as `nixos-rebuild switch --flake /etc/nixos`".
- `nh os switch` is the same command: per nix-community/nh docs (`docs/README.md`,
  command table), `nh os switch . -H <host>` ≡ `nixos-rebuild switch
  --flake .#<host>` (with the caveat that `nh os` reimplements
  `nixos-rebuild-ng` and does not yet have full feature parity). So with
  `home-manager.users.podman` wired in `nixos-builder.nix`, every `nh os
  switch` on lumquat re-runs the podman user's activation, including
  `home.activation` entries.

### 3. The source repo stays on disk at `~/.local/share/chezmoi`

- chezmoi's default source directory is `~/.local/share/chezmoi`
  (`reference/source-state-attributes.md`). `chezmoi init <repo>` clones the
  repo into the source directory and generates the config file if the repo
  contains `.chezmoi.$FORMAT.tmpl` (`reference/commands/init.md`); `--apply`
  additionally runs `chezmoi apply` after init.
- `chezmoi apply` requires the source directory to exist (the apply command is
  annotated `requiresSourceDirectory` in `internal/cmd/applycmd.go`), so the
  repo must be initialized at least once before any unattended apply.
- Periodic maintenance stays manual: `chezmoi update` pulls (`git pull
  --autostash --rebase`) and applies by default (`reference/commands/update.md`),
  so the user can run `chezmoi update` (or plain `chezmoi apply`) whenever —
  nothing about the switch wiring removes the repo or blocks this.
- No `programs.chezmoi` exists to "initialize" the repo (finding 1); chezmoi's
  own `init` is the only initializer. Our repo itself is a subdirectory-root
  repo: `.chezmoiroot = home`, per this repo's `.chezmoiroot` file and the
  documented `.chezmoiroot` mechanism (`user-guide/advanced/
  customize-your-source-directory.md`).

### 4. Interaction with our constraints (headless, no BWS session)

- **lumquat is already non-interactive in our templates.** `home/.chezmoi.toml.tmpl`
  hardcodes `lumquat` → `headless = true`, `personal = false` (no `stdinIsATTY`
  branch is reached for lumquat). The `promptBoolOnce` fallback only fires for
  *unknown* hostnames when stdin is a TTY; non-TTY defaults to
  `ephemeral/headless`. The only linux `.chezmoiscripts` entry is guarded to
  hostname `thinkpad` and needs sudo — not run for lumquat. So template
  rendering for podman/lumquat does not prompt.
- **BWS blocker: the git config template calls `bws` unguarded.**
  `home/private_dot_config/git/config.tmpl` sets
  `signingkey = "{{ index (output "bws" "secret" "get" "b84feb92-…" | fromJson) "value" | trim }}"`
  with no condition. `bws` authenticates via `BWS_ACCESS_TOKEN` for a machine
  account (bitwarden.com/help/secrets-manager-cli/: "You can authenticate a CLI
  session by saving an environment variable BWS_ACCESS_TOKEN …"); in a
  token-less environment the command fails and chezmoi's `output` propagates
  the failure, aborting `chezmoi apply`.
- **Our architecture has no user-level BWS channel on lumquat.** Per
  `SECRET_SYNC.md` (nix-config): on NixOS the BWS bootstrap token lives only at
  `/var/lib/secrets/bws-access-token` (root:root 0600), delivered to systemd
  services via `LoadCredential`; "the devshell is not a secret channel there".
  Nothing provisions `BWS_ACCESS_TOKEN` for the `podman` user, and the ticket's
  constraint is that apply must run with no BWS session at all. So an
  unattended `chezmoi apply` for podman **requires** neutralizing the
  `signingkey` template (e.g. wrap in `{{ if .personal }}…{{ end }}`, or
  ignore the file for the podman user) — this is a prerequisite, not an option.
- **chezmoi is not yet installed for podman.** `modules/infra/hm-infra.nix`
  enables `my.cliTools`, which pulls `modules/features/cli-tools.nix`
  (bat, gh, neovim, …) — **without** chezmoi. chezmoi appears only in
  `cli-system-tools.nix`, enabled solely on the darwin hosts
  (`hosts/bergamot/capabilities.nix`, `hosts/miraclemax/capabilities.nix`).
- **Non-interactive apply**: official docs recommend `chezmoi apply --force` to
  suppress the overwrite prompt for files modified since chezmoi last wrote
  them (`user-guide/advanced/use-chezmoi-with-watchman.md`: "For `chezmoi
  apply`, you can use the `--force` flag to suppress prompts to overwrite files
  that have been modified since chezmoi last wrote them"). This is the exact
  unattended scenario (no terminal).

## Recommendation

Use **`home.activation`** (option 2) — not `programs.chezmoi`, which does not
exist upstream and cannot be made to. Add chezmoi to the podman user's
packages, and run a bootstrap-then-apply activation entry that is idempotent
(`init` only clones when the repo is missing; `apply --force` is non-interactive).

Exact wiring (to be placed in the podman user's HM modules, e.g. in
`modules/infra/hm-infra.nix` alongside `my.cliTools = true;`, or in a new
`modules/infra/hm-chezmoi.nix` registered into the deferred HM module set in
`modules/infra/nixos-builder.nix`):

```nix
{ lib, pkgs, ... }: {
  my.cliTools = true;

  home.packages = [ pkgs.chezmoi ]; # nixpkgs pkgs/by-name/ch/chezmoi (2.72.0)

  home.activation.chezmoiApply = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run test -d "$HOME/.local/share/chezmoi/.git" \
      || run ${pkgs.chezmoi}/bin/chezmoi init https://github.com/ashebanow/dotfiles.git
    run ${pkgs.chezmoi}/bin/chezmoi apply --force
  '';
}
```

Rationale and properties:

- **Runs on every `nh os switch`**: the `home-manager-podman.service` unit
  defined by home-manager's NixOS module re-runs the podman user's activation
  on every system rebuild (`installation/nixos.html`), and `nh os switch` ≡
  `nixos-rebuild switch --flake .#lumquat` (nh docs).
- **Idempotent and safe ordering**: `entryAfter ["writeBoundary"]` satisfies
  home-manager's requirement that side-effectful blocks run after the write
  boundary (`modules/home-environment.nix`); the `run` helper honors
  `DRY_RUN`/`VERBOSE` (documented on `home.activation`).
- **Repo stays for periodic use**: source dir stays at
  `~/.local/share/chezmoi` (this repo's `.chezmoiroot = home` layout);
  user runs `chezmoi update` / `chezmoi apply` at will (`reference/commands/update.md`).
- **No BWS needed**: the only BWS-dependent template in the repo
  (`git/config.tmpl` signingkey) must be made `{{ if .personal }}`-guarded (or
  ignored for podman) before this is safe; lumquat is already `headless`/
  non-personal in `home/.chezmoi.toml.tmpl`, so no interactive prompts occur.
- **First-switch bootstrap**: the activation clone runs as the `podman` user
  and needs network + git access; if outbound HTTPS is restricted on lumquat,
  pre-seed the repo (e.g. `sudo -u podman chezmoi init …` or clone as root and
  chown) before the first switch with this module.

Options used: `home.packages`, `home.activation.chezmoiApply`
(`lib.hm.dag.entryAfter ["writeBoundary"]`), plus the existing
`home-manager.users.podman` NixOS wiring already present in `nixos-builder.nix`.
No `programs.chezmoi` options exist to use.

## Sources

Primary-source citations per claim (all fetched 2026-09-01):

- **Home-manager module absence** — `github.com/nix-community/home-manager`
  git tree API `git/trees/master?recursive=1` (commit `1dc2d1f7`, 2026-09-01;
  full 5,475-entry tree, zero `chezmoi` paths); commits API
  `commits?path=modules/programs/chezmoi.nix` (0 commits); search API
  `search/issues?q=chezmoi+repo:nix-community/home-manager` (no PRs; unrelated
  issue #3346); manual `3rd-party/collections.html` (no chezmoi).
- **chezmoi docs absence** — `twpayne/chezmoi` master git tree
  (`assets/chezmoi.io/docs/`, 343 files; only home-manager hit is
  `links/articles.md.yaml`, a migration-away article).
- **`home.activation`** — `modules/home-environment.nix` (option at line ~470:
  type `lib.hm.types.dagOf types.str`, default `{}`, example
  `lib.hm.dag.entryAfter ["writeBoundary"]`, writeBoundary = `entryAnywhere`,
  `run`/`DRY_RUN`/`VERBOSE` helpers); `modules/lib/types-dag.nix`
  (`maybeConvert` → bare strings become `entryAnywhere`); manual
  `internals/activation.html` (activation script = init + serialized
  `home.activation` blocks).
- **Runs on every switch** — manual `installation/nixos.html` ("By default,
  Home Manager activates each configured user during boot and system rebuilds
  through a NixOS system service: `systemctl status "home-manager-$USER.service"`");
  manual `nix-flakes/nixos.html` ("automatically rebuilt with the system …
  `nixos-rebuild switch --flake /etc/nixos`"); `nixos/default.nix`
  (`systemd.services."home-manager-<user>"`, `wantedBy = multi-user.target`,
  `ExecStart = … activate`; `startAsUserService` variant via
  `system.userActivationScripts.home-manager`).
- **nh** — `github.com/nix-community/nh` `docs/README.md` (command table:
  `nh os switch . -H <host>` ≡ `nixos-rebuild switch --flake .#<host>`; "`nh
  os` … does not yet provide full feature parity with `nixos-rebuild`").
- **Source dir / init / update / apply** — `reference/source-state-attributes.md`
  (default `~/.local/share/chezmoi`); `reference/commands/init.md` (clone repo
  into source dir, generate config from `.chezmoi.$FORMAT.tmpl`, `--apply`);
  `reference/commands/update.md` (`git pull --autostash --rebase` + apply by
  default); `internal/cmd/applycmd.go` (`requiresSourceDirectory` annotation);
  `user-guide/advanced/use-chezmoi-with-watchman.md` (`--force` suppresses
  overwrite prompts — the documented unattended pattern);
  `user-guide/advanced/customize-your-source-directory.md` (`.chezmoiroot`).
- **nixpkgs chezmoi** — `pkgs/by-name/ch/chezmoi/package.nix` on nixpkgs master
  (pname `chezmoi`, version `2.72.0`).
- **bws auth** — `bitwarden.com/help/secrets-manager-cli/` ("You can
  authenticate a CLI session by saving an environment variable
  `BWS_ACCESS_TOKEN` …"), cross-checked against nix-config
  `SECRET_SYNC.md` (token is root-only `/var/lib/secrets/bws-access-token`,
  `LoadCredential` delivery, "the devshell is not a secret channel" on NixOS).
- **Local repo templates** — `home/.chezmoi.toml.tmpl` (lumquat →
  `headless`/non-`personal`; `promptBoolOnce` only for unknown hosts with TTY),
  `home/.chezmoiignore.tmpl` (OS-only gating), `home/private_dot_config/git/config.tmpl`
  (unguarded `output "bws" …` signingkey), `home/.chezmoiscripts/linux/` (single
  `thinkpad`-guarded script), `.chezmoiroot` = `home`.
- **nix-config wiring (read-only)** — `modules/infra/nixos-builder.nix`
  (`home-manager.nixosModules.home-manager` + `home-manager.users.podman` with
  `hm-infra.nix` + deferred HM modules), `modules/infra/hm-infra.nix`
  (`my.cliTools = true`), `modules/features/cli-tools.nix` / `cli-system-tools.nix`
  (package lists; chezmoi only in `cliSystemTools`, enabled on
  `hosts/bergamot|miraclemax/capabilities.nix`), `hosts/lumquat/configuration.nix`
  (headless flags, `my.baseUsername = "podman"`), `lib/my-options-module.nix`
  (option definitions).
