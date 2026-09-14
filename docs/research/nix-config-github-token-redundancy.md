# Is `nix.conf.tmpl`'s GitHub access-token redundant with nix-config's own auth?

**Ticket:** https://linear.app/boxbow/issue/BOX-173 (map: BOX-165, HEADLESS DOTFILES)
**Repos:** dotfiles `~/.local/share/chezmoi`, nix-config `~/Development/nix/nix-config/main`
**Method:** read-only. No tracked file in either repo was modified except this document (dotfiles). No BWS secret value was fetched or printed; only item IDs and env-var names appear below.

---

## Verdict (TL;DR)

**Delete the `access-tokens` block.** It is dead weight on lumquat *and* on every other host.

- nix-config sets no `access-tokens` anywhere and every one of its flake inputs is **public**. There is no private flake input on lumquat for the token to authenticate (`flake.nix:5-80`, `flake.lock`).
- The one credential lumquat actually needs for the Nix cache layer is **FlakeHub**, and nix-config already delivers it host-side via BWS → secretspec → `determinate-nixd auth login` at boot (`modules/infra/nix/flakehub.nix:22-51`). That has nothing to do with `access-tokens`.
- The `~/.config/nix/nix.conf` file's own header claims the token is "for private flake inputs" (`nix.conf.tmpl:5-6`). **No private flake input exists**, so the claimed purpose is unrealised.
- No service, timer, script, `nh`/colmena path, or `just` recipe in nix-config performs a *GitHub* fetch that a GitHub token would authenticate. `gh` token (the other BWS consumer) is likewise interactive/devshell-only.

Recommendation per question is at the end. The block can be removed from `nix.conf.tmpl`; the `BWS_ACCESS_TOKEN` export in `hm-infra.nix` must **stay** (it still feeds `gh/hosts.yml.tmpl`, if that even survives — see Q5).

---

## Q1 — Is the `access-tokens` line redundant? Is it needed for user-level nix?

**Verdict: redundant / dead weight. Not needed for any operation on lumquat.**

### Nix semantics of user-level vs daemon-level `access-tokens`

The decisive primary source is the Nix manual, `nix.conf` reference (nix.dev, Nix 2.35.2):

> "The system-wide configuration file `nix.conf` in the configuration directory … **Values loaded in this file are not forwarded to the Nix daemon.** The client assumes that the daemon has already loaded them."
> — https://nix.dev/manual/nix/latest/command-ref/conf-file.html, "Configuration file"

And the `access-tokens` setting itself:

> "Access tokens used to access protected GitHub, GitLab, or other locations requiring token-based authentication. … Example `~/.config/nix/nix.conf`: `access-tokens = github.com=23ac...b289 ...`"
> — same page, `access-tokens`

The mechanics:

- `access-tokens` is consumed **by the process that performs the flake input fetch**. A flake input is fetched either by the **client** (`nix flake lock`, and any eval that has to resolve a `github:` ref it does not already have in the store/lock) or by the **daemon** when the client delegates (`nix build` of a derivation whose input must be fetched).
- Because a user-level `~/.config/nix/nix.conf` is **not forwarded to the daemon**, a token placed there only ever authenticates fetches the *user's own client process* performs. It cannot make the daemon authenticate anything.
- Therefore user-level `access-tokens` is the right *mechanism* for user-initiated fetching of a **private** `github:` flake input (the documented use case: `nix flake lock` in a repo with a private input).

**But there is no private input.** `flake.nix:4-80` lists every input — `nixos/nixpkgs`, `DeterminateSystems/determinate` (flakehub), `hercules-ci/flake-parts`, `vic/import-tree`, `nix-community/home-manager`, `nix-darwin/nix-darwin`, `zhaofengli/nix-homebrew`, `homebrew/homebrew-core`, `homebrew/homebrew-cask`, `hraban/mac-app-util`, `nixos/nixos-hardware`, `lukasl-dev/pi.nix`, `ashebanow/worktrunk` — all public. `flake.lock` contains no private ref. Public inputs fetch anonymously; `access-tokens` is never consulted.

The file's own comment (`nix.conf.tmpl:5-6`, "This file also carries the GitHub access token (from bws) for private flake inputs") describes a purpose that does not exist in the current configuration. This is the strongest single piece of evidence: the token's stated job is vacant.

For `nix develop` / `nix build` in the nix-config devshell (`modules/infra/devshell.nix:25-61`) and for `just switch` etc., all inputs are public and already locked — no GitHub auth participates.

## Q2 — Does nix-config deliver a GitHub token to `podman` by another route?

**Verdict: No. There is no GitHub token on lumquat at all.**

- `grep -rn "access-tokens"` across all `*.nix`, `*.toml`, `*.sh`, `*.md`, `justfile` in nix-config → **zero hits**.
- `grep -rniE "GITHUB_TOKEN|GH_TOKEN|gh auth|netrc|credential.helper"` across the same → **zero hits**.
- `secretspec.toml` (the whole manifest) declares no GitHub token: host scope is only `TAILSCALE_AUTH_KEY`, `FLAKEHUB_TOKEN` (`secretspec.toml:39-40`, `:72-73`); the container scopes are tailscale keys + LLM API keys (`:75-87`).
- There is no `LoadCredential` for a GitHub token anywhere; the only credentials are the BWS bootstrap `access_token` (`modules/features/secrets.nix:57`) and the two file-backed secrets it resolves.
- `modules/infra/hm-infra.nix:26` exports `BWS_ACCESS_TOKEN` to the podman user, but **only around the `chezmoi apply` activation** (comment `:23-25`), so chezmoi templates that need it render. It is a chezmoi-plumbing export, not a nix-config auth route.

So the *only* GitHub credential that exists on lumquat is the one chezmoi writes. It is not duplicated; it is also not needed.

## Q3 — FlakeHub / determinate-nixd: per-user or per-host?

**Verdict: per-host (daemon/daemon-socket state), delivered by nix-config; the dotfiles shell hook is not needed on lumquat.**

`modules/infra/nix/flakehub.nix` is explicit:

- Header comment `:1-13`: "cache.flakehub.com is an active substituter (see `./caches.nix`) but requires a FlakeHub login. **determinate-nixd stores auth state itself over its daemon socket** — there is no nix.conf knob for it. This module provisions the FlakeHub token from BWS … and logs nixd in once at boot, re-running whenever the nixd binary changes". Gated on `determinate.enable && (my.access || my.llm)` (`:21`).
- The unit `flakehub-nixd-auth.service` (`:22-51`) is `wantedBy = ["multi-user.target"]` (`:24`), `wants`/`after` `host-secrets-populate.service` and `nix-daemon.service` (`:25-30`), and runs
  `determinate-nixd auth login token --token-file /run/secrets/flakehub-token` (`:36`), retrying hourly (`:38-39`) and re-running when nix/nixd change (`:47-50`).
- The token file is written by `host-secrets-populate.service` (`modules/features/secrets.nix:22-25,38-60`), which resolves the `host` scope through `secretspec run -P production -S host` with `SECRETSPEC_PROVIDER=bws-service` and `LoadCredential=access_token:…` (`:51-58`). `FLAKEHUB_TOKEN` → BWS item `NIX_FLAKEHUB_CACHE_TOKEN` (`secretspec.toml:40,72-73`; `SECRET_SYNC.md:148-169`).
- `cache.flakehub.com` is an active substituter with its public key trusted (`modules/infra/nix/caches.nix:3,11`).

**Auth is per-host.** `determinate-nixd` holds the login in its own daemon state and applies it to the daemon's substitution/fetch path. A non-interactive `nix` invocation as `podman` — inside a systemd unit or a plain SSH command with no interactive shell — authenticates to `cache.flakehub.com` because the **daemon** is already logged in, independent of any shell hook. Nothing in the auth path touches the user's shell environment.

The dotfiles' `_bws_flakehub_login` (`home/private_dot_config/shell/secrets.sh:123-151`) is:

- guarded by `is_interactive || return 0` (`:124`), and invoked at `:151` from `.zshenv` (`zsh/dot_zshenv.tmpl:37`) / `bashrc.d/999_secrets.sh.tmpl:4` — both interactive-only contexts;
- reading `FLAKEHUB_TOKEN` from the shell's BWS cache, then running the same `determinate-nixd auth login token --token-file` the systemd unit runs (`:143`).

So on lumquat it is a **duplicate of `flakehub-nixd-auth.service`** that (a) only fires in an interactive shell and (b) is redundant because boot already logged nixd in. It is not what makes FlakeHub work on lumquat; the systemd unit is. (On macOS the shell hook is the only mechanism, since there is no NixOS module — but lumquat is the case here.)

## Q4 — Does anything in nix-config already expect a GitHub credential on the host?

**Verdict: No.**

- Systemd units present on lumquat: `flakehub-nixd-auth` (`flakehub.nix:22`), `host-secrets-populate` (`secrets.nix:38`), `bifrost-compose` (`bifrost.nix:42`), `memory-compose` (`memory.nix:121`), `memory-health-check` (`:163`, timer `:187`), `memory-backup` (`:198`, timer `:224`), `podman-network-llm-internal` (`llm.nix:132`). None of these fetch a GitHub flake input or call `gh`.
- Every `nix` invocation in the repo is either the devshell marker comment (`devshell.nix:29`) or a **human-run `just` recipe**: `justfile:26` (`nix flake show`), `:30` (`nix flake update`), `:35` (`nix develop .# -c alejandra .`), `:43` (`nix build …lumquat…vm`), `:102` (`nix build ~/Development/nix/zmx#zmx`). All against public inputs.
- `justfile:20` does `import "~/.justfile"`, and the comments (`:5-12`) say `~/.justfile` is installed by chezmoi (`home/dot_justfile.tmpl`). `grep -niE "github|access-token|GH_TOKEN|BWS|token" home/dot_justfile.tmpl` → **no hits**: the imported recipes reference no GitHub credential.
- `nix-config` carries `colmena` and `nix-output-monitor` in `cli-system-tools.nix` (`:17,31`), but no colmena deployment is scripted as a unit here; deployments are operator-driven like the `just` recipes.
- The `devshell.nix:46` `gh` package and `:43` `bws` are interactive devshell tools, not host automation.

No unit, timer, or recipe expects a GitHub token on the host. The chezmoi side is neither satisfying a hidden requirement nor being relied upon for one.

## Q5 — Bonus: `gh/hosts.yml.tmpl` (personal gh OAuth token)

**Verdict: needed only for interactive `gh` inside the `nix develop` devshell — not for anything nix-config *does* on lumquat.**

- `home/private_dot_config/gh/hosts.yml.tmpl:5,9` write the personal oauth token from BWS item `5a333d5a-d7aa-46cb-98e1-b479014cd326` (the same item the nix.conf block used). `git_protocol: ssh` (`:7`).
- `gh` is installed **only in the nix-config devshell** (`modules/infra/devshell.nix:46`); it is not in the lumquat host closure. The prior inventory reached the same conclusion: "gh | **T3 only** | `~/.config/gh/{config.yml,hosts.yml}` | tier-3-only target — devshell still runs on the box" (`docs/research/headless-managed-inventory.md:256`), and "chezmoi writes `~/.config/gh/hosts.yml` with a personal OAuth token … nix-config itself does not manage gh config. This is the token the map wants to replace with a GitHub App identity" (`:364-366`).
- Nothing in nix-config *invokes* `gh` — no unit, timer, script, or `just` recipe does. `git_protocol: ssh` plus the loaded ssh-agent keys (`secrets.sh:156-174`) are what `git push`/`git fetch` over GitHub use interactively; `gh`'s oauth_token is only for `gh` API/CLI use.
- On headless the ssh path is a separate question (`.ssh` is excluded from headless per `home/.chezmoiignore.tmpl:100`), so the practical value of a personal `gh` token on lumquat is limited to an interactive `gh` in the devshell.

Same shape as the nix token: **cheap to keep for interactive devshell use, but not load-bearing for any headless/nix-config operation.** The map (BOX-165) already contemplates replacing this personal identity with a GitHub App.

---

## Consumers of BWS item `5a333d5a-d7aa-46cb-98e1-b479014cd326`

Exactly three template references in the dotfiles repo:

- `home/private_dot_config/nix/nix.conf.tmpl:13` — the block under review.
- `home/private_dot_config/gh/hosts.yml.tmpl:5` and `:9` — the gh OAuth token.

Nothing in nix-config references it (nix-config uses its own Homelab-project items and never names a GitHub token).

## `chezmoi apply` interaction (why the block does not break apply if deleted)

`modules/infra/hm-infra.nix:22-30` exports `BWS_ACCESS_TOKEN` from the bootstrapped root token before `chezmoi apply --force`. Both `nix.conf.tmpl:12` and `hosts.yml.tmpl:4,8` are gated on `env "BWS_ACCESS_TOKEN"`, so they render when the token is present and quietly skip when it is not. Deleting the `access-tokens` block changes nothing about template rendering: the file keeps `accept-flake-config`, `auto-optimise-store`, `cores`, `max-jobs`, and `extra-experimental-features` (`nix.conf.tmpl:8-16`), and no `BWS_ACCESS_TOKEN` guard is needed for them. The `BWS_ACCESS_TOKEN` export in `hm-infra.nix` remains required while `gh/hosts.yml.tmpl` keeps its guard (or if that template is pruned, the export could be narrowed to whatever still needs it).

## Recommendation

| # | Question | Verdict | Action |
|---|----------|---------|--------|
| 1 | `access-tokens` redundant? | **Yes — dead weight.** No private flake input exists; the token's stated purpose (`nix.conf.tmpl:5-6`) is unrealised. | **Delete** the `{{- if env "BWS_ACCESS_TOKEN" }} access-tokens … {{- end }}` block (`nix.conf.tmpl:12-14`). |
| 2 | Another GitHub-token route in nix-config? | **No** — nix-config has no GitHub token at all. | No change on the nix-config side. |
| 3 | FlakeHub per-user or per-host? | **Per-host**, via `flakehub-nixd-auth.service`; dotfiles `_bws_flakehub_login` is an interactive duplicate. | Keep nix-config as-is. Flag `_bws_flakehub_login` (`shell/secrets.sh:123-151`) as redundant-on-lumquat (still needed on macOS). |
| 4 | nix-config expects a GitHub credential? | **No** unit/timer/script/recipe. | No change. |
| 5 | `gh` personal token needed? | **Interactive devshell only.** | Keep for now; the map already plans to replace it with a GitHub App. |

**Concrete delete:** remove lines 12–14 of `home/private_dot_config/nix/nix.conf.tmpl`, and update the header comment (`:5-6`) so it no longer claims a token for private flake inputs. Optional follow-up: prune the now-unused `BWS_ACCESS_TOKEN` guard rationale in `hm-infra.nix:23-25` if `gh/hosts.yml.tmpl` is also pruned.

## Sources

Primary:
- Nix manual, `nix.conf` — https://nix.dev/manual/nix/latest/command-ref/conf-file.html ("Configuration file": system-wide values "are not forwarded to the Nix daemon"; `access-tokens` description and `~/.config/nix/nix.conf` example).
- nix-config: `flake.nix:4-80`, `flake.lock`, `modules/infra/nix/nix.nix:33-45`, `modules/infra/nix/caches.nix:1-26`, `modules/infra/nix/flakehub.nix:1-52`, `modules/infra/nix/default.nix:4-6`, `modules/infra/hm-infra.nix:13-30`, `modules/infra/devshell.nix:25-61`, `modules/features/secrets.nix:13-60`, `secretspec.toml:21-87`, `SECRET_SYNC.md:40-169`, `justfile:1-107`, `hosts/lumquat/configuration.nix:3-41`.
- dotfiles: `home/private_dot_config/nix/nix.conf.tmpl:1-16`, `home/private_dot_config/gh/hosts.yml.tmpl:1-11`, `home/private_dot_config/shell/secrets.sh:9,49-151`, `home/private_dot_config/zsh/dot_zshenv.tmpl:35-37`, `home/private_dot_config/bashrc.d/999_secrets.sh.tmpl:2-4`, `home/.chezmoiignore.tmpl:46-106`.

Prior art in this repo:
- BOX-167 / `docs/research/headless-managed-inventory.md` §3.1 (`:239,256`), §4.1 (`:335-339`), §4.2 (`:351-366`).
