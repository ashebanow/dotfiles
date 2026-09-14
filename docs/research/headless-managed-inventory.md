# The headless managed-target inventory vs what nix-config installs on lumquat

**Ticket:** https://linear.app/boxbow/issue/BOX-167 (map: BOX-165, HEADLESS DOTFILES)
**Date:** 2026-09-12 (research pass)
**Scope:** Ground truth for the pruning pass. Part A: the full set of chezmoi-managed
targets a headless machine receives. Part B: the nix-config tool inventory on
lumquat in three tiers. Part C: the per-target join (the pruning ticket's
measuring stick). Part D: system-level config that needs podman-user config, and
places chezmoi and nix-config fight.

Both repos were read-only. Evidence is file + line references; every count is
reproducible from the method in §5.

**HEADLINE:** a headless (`headless = true`, os = linux) machine receives
**153 managed target entries** (`chezmoi managed` semantics: files + symlinks +
directories) from the current source tree + `.chezmoiignore.tmpl`. Grouped by
tool that is **~35 tool groups**, of which a handful are **wrong by the map's
rule** (desktop/GUI/personal artefacts that leak through broken ignore patterns)
and a few are **gaps** (installed tools with no config). See §3.

---

## 1. Part A — what the `podman` home actually receives today

### 1.1 Method (and why it is not a raw `chezmoi managed`)

This checkout is a macOS personal machine (`miracle_max`, `headless = false`),
so `chezmoi managed` here reflects darwin+non-headless and is **not** the answer.
`.chezmoi.os` is taken from the Go runtime and cannot be overridden via
`--override-data`, so a linux render cannot be produced by `chezmoi` alone.

The method used:

1. Render `home/.chezmoiignore.tmpl` with `.chezmoi.os = "linux"`,
   `.headless = true` using a minimal standalone renderer (`/tmp/render_ignore.py`).
   The template uses only `{{ if ne .chezmoi.os "…" }}`, `{{ if .headless }}`,
   `{{ end }}`, and comments — no other constructs.
   **The renderer was validated against `chezmoi execute-template` for the
   darwin+headless case: byte-identical output.**
2. Enumerate every entry under `home/`, decode chezmoi source names
   (`dot_`, `private_`, `readonly_`, `executable_`, `empty_`, `symlink_`,
   `exact_`, `run_*`, `.tmpl`) into target paths, and apply the rendered root
   ignore plus per-directory `.chezmoiignore` files with doublestar matching.
   **The decoder was validated against `chezmoi managed` for this machine's
   (darwin, non-headless) config: the only differences were the special
   `.chezmoiscripts/*` entries and filenames containing spaces — both artefacts
   of the comparison harness, not the decoder.**
3. Cross-checked the two broken-pattern findings (§1.4) directly against
   `chezmoi` in a sandbox source tree.

### 1.2 The rendered headless+linux ignore list

58 patterns. The `ne "darwin"` block (11 macOS-only patterns) is **inactive** on
linux; the `ne "linux"` block is active; the `.headless` block is active. Full
render at `home/.chezmoiignore.tmpl` lines 1–89.

Notable: the headless block's stated purpose (comment, lines 33–36) is "no
desktop, no personal secrets/dev tools". The paths it lists that **do** land
correctly are the GUI trees (`.config/{hypr,niri,waybar,gtk-*,sway*,wlogout,
xfce4,...}`), terminal/app configs (`.config/{kitty,wezterm,ghostty,tmux,
lazygit,zed,atuin,jj,television,hop,starship.toml}`), zsh (`.config/zsh`),
personal secrets (`.claude`, `.gnupg`, `.hermes`, `.lazyssh`, `.ssh`),
`Development`, `.rumdl.toml`, and `Library`.

### 1.3 The surviving managed target set (grouped by tool)

153 entries. Directories are shown as `dir/`; every file under a surviving
directory also survives.

| # | Tool / purpose | Managed targets |
|---|---|---|
| 1 | **bash (login/interactive)** | `~/.bashrc`, `~/.bash_profile`, `~/.hushlogin` |
| 2 | **shared shell layer** | `~/.config/shell/{env,paths,core,hooks,productivity,version-control,utility,secrets,devtools,shortcuts,starship-nix-gate}.sh` |
| 3 | **bash rc.d** | `~/.config/bashrc.d/{010_history.sh,020-prompt.sh,999_secrets.sh,starship-gate.sh}` |
| 4 | **zsh entrypoint (dead on headless)** | `~/.zshenv` |
| 5 | **git** | `~/.config/git/{config,attributes,ignore}` |
| 6 | **gh** | `~/.config/gh/{config.yml,hosts.yml}` |
| 7 | **nix (client)** | `~/.config/nix/nix.conf` |
| 8 | **just** | `~/.justfile` |
| 9 | **bat** | `~/.config/bat/{config,themes/*}` |
| 10 | **btop** | `~/.config/btop/{btop.conf,themes/*}` |
| 11 | **fastfetch** | `~/.config/fastfetch/*` (incl. `assets/`, `{2,6,7,10,foot,kitty,min,test}.jsonc`) |
| 12 | **neovim** | `~/.config/nvim/{init.lua,.luarc.json,LICENSE,README.md,lsp/*,snippets/*}` |
| 13 | **secretspec** | `~/.config/secretspec/config.toml` |
| 14 | **worktrunk** | `~/.config/worktrunk/config.toml` |
| 15 | **systemd (user units)** | `~/.config/systemd/user/{sunset.service,sunset.timer,tmux.service}` |
| 16 | **podman containers (quadlet)** | `~/.config/containers/systemd/mealie.container` |
| 17 | **devenv** | `~/.config/devenv/config.yaml` |
| 18 | **zennotes** | `~/.config/zennotes/config.toml` |
| 19 | **vim** | `~/.vimrc` |
| 20 | **local bin scripts** | `~/.local/bin/{extract,find-dirty-gits,git-open,git-prompt-path,git-st,list-cloudflare-ips,mac_logout_handler.zsh,nerdfont-smoke-test,rename_dot_files.sh,setup-bws-keyring.sh,ssh_conf_preview.awk,ssh_hosts,wttr}` |
| 21 | **pi agent** | `~/.pi/**` — `APPEND_SYSTEM.md`, `auth.json`, `models.json`, `settings.json`, `trust.json`, `extensions/*`, `skills/graphify/**`, `themes/gruvbox-hard.json` |
| 22 | **AGENTS.md** | `~/AGENTS.md` |
| — | **LEAKS (see §1.4)** | `~/.config/.obsidian/**`, `~/.config/syncthingtray.ini`, `~/.config/YouTube Music/catpuccin_mocha.css`, `~/.config/Code/User/{extensions,keybindings,settings}.json` |
| — | **pi extension leak** | `~/.pi/agent/extensions/editable-worktrunk.ts` (a `./chezmoiignore` in `dot_pi/agent/` lists it — see §1.4) |

The shared shell layer (`#2`) deserves the note that four of its chunks are
**excluded on headless by line-level template conditionals, not by
`.chezmoiignore`**: `devtools.sh` and `shortcuts.sh` are personal-only and are
never sourced (`.bashrc.tmpl` has exactly two `{{ if not .headless }}` gates).
`starship-nix-gate.sh` and `starship-gate.sh` are present but inert because
starship is not installed and starship.toml is excluded — dead prompt
machinery the map explicitly targets.

`secrets.sh` and `bashrc.d/999_secrets.sh` **do land** as files (they are not in
the headless ignore block); the BOX-165 note "`shell/secrets.sh` and
`bashrc.d/999_secrets.sh` are whole-file excluded on headless" is therefore
**not currently true of the template** — they ship, and both are `command -v`
guarded / env-guarded inside. That is a drift point between the map's stated
decision and the template, flagged here.

### 1.4 Broken ignore patterns — desktop/personal content that leaks through

Three patterns in the headless block do not match the target paths they were
meant to exclude. Verified empirically with `chezmoi` in a sandbox (§5):

| Ignore pattern (headless block) | Actual target path | Result |
|---|---|---|
| `.config/obsidian` | `~/.config/.obsidian` (source `dot_obsidian` → leading `.`) | **not excluded** |
| `.config/syncthingtray` | `~/.config/syncthingtray.ini` | **not excluded** |
| (not listed at all) | `~/.config/YouTube Music/**`, `~/.config/Code/User/**` | **not excluded** |

`chezmoi` matches patterns against the **target path**, not the source path
(established in `chezmoi-bws-headless.md` §3). `.config/obsidian` ≠
`.config/.obsidian`; `.config/syncthingtray` ≠ `.config/syncthingtray.ini`.
Verified:

```
$ chezmoi --source ./home --destination ./dest managed   # home/.chezmoiignore: ".config/obsidian"
.config
.config/.obsidian
.config/.obsidian/f.txt
```

There is also a **source-side** ignore bug: the per-directory
`home/dot_pi/agent/.chezmoiignore` lists `extensions/editable-worktrunk.ts`, but
the source file is named `worktrunk.ts` and is symlinked via
`symlink_worktrunk.ts.tmpl` → `~/.pi/agent/extensions/worktrunk.ts`. The file
survives as `editable-worktrunk.ts` **and** `worktrunk.ts` (both appear in the
managed set), so the pi extension is double-provisioned. Worth confirming when
the pi pruning ticket lands.

### 1.5 Drift vs the BOX-123 inventory decision

BOX-123's recorded "kept managed on headless" list: *`~/.pi`, gh, systemd,
fastfetch, nix, containers, AGENTS.md*. Compared with the actual set above:

| BOX-123 claim | Template today | Drift |
|---|---|---|
| kept `~/.pi` | kept, incl. `private_auth.json` | none — but this is the map's `Not yet specified` item |
| kept `gh` | kept | none |
| kept `systemd` | kept (3 user units) | none — note the units include `tmux.service` for a tool excluded on headless, and `sunset.service` (desktop redshift-style) |
| kept `fastfetch` | kept | none |
| kept `nix` | kept | none |
| kept `containers` | kept (mealie quadlet) | none |
| kept `AGENTS.md` | kept | none |
| (not mentioned) | `~/.config/{bat,btop,nvim,secretspec,worktrunk,devenv,zennotes}` also kept | **additional** to the BOX-123 list |
| (not mentioned) | `~/.config/{.obsidian,syncthingtray.ini,YouTube Music,Code}` leak | **new** — the broken patterns above |
| "`shell/secrets.sh` … whole-file excluded" (BOX-165 note) | ships | **claim not true of template** |

---

## 2. Part B — what nix-config installs on lumquat

Verified by evaluating the actual flake (`nix eval --json`) as well as reading
the modules. All paths under `~/Development/nix/nix-config/main`.

### Tier 1 — `environment.systemPackages` (system-wide, on podman's PATH)

Declared in `modules/features/base.nix:78-92` (the `my.base` module, enabled
by `hosts/lumquat/configuration.nix:12`), plus `modules/features/zmx.nix:15`
(`my.zmx = true`).

**Module-declared tier 1:** `btop bws curl eza ghostty.terminfo git htop iputils
nh secretspec sudo vim wget` (base.nix) **+ `zmx`** (zmx.nix).

Directly from `base.nix` (also lumquat-enabled): `programs.direnv.enable = true`
(`base.nix:27`) pulls **`direnv`** into `systemPackages` (confirmed in the
eval). `services.openssh`/`networking`/etc. pull their own closure, but those
are not user tools.

Confirmed by eval (`nix eval .#nixosConfigurations.lumquat.config.environment.systemPackages`):
the declared set above is present, plus the NixOS baseline closure (bash,
coreutils-full, procps, util-linux, openssh, podman, tailscale, zsh, …). The
ticket's hint list for tier 1 is **correct** and additionally confirmed to
include `zmx` and `direnv`.

### Tier 2 — `home.packages` for `podman` (user-level)

Wired by `modules/infra/hm-infra.nix:18` (`my.cliTools = true`) and built via
`modules/infra/nixos-builder.nix` (`home-manager.users.podman` imports
`hm-infra.nix` + all deferred HM modules). Note lumquat does **not** enable any
of the topical `cli*Tools` flags — only `my.cliTools`.

`modules/features/cli-tools.nix:12-27` declares:
`bat bottom coreutils-full curl dig eza fastfetch fd fzf just neovim ripgrep
wget zoxide` — plus `hm-infra.nix:19` adds `chezmoi`.

Confirmed by eval (`…home-manager.users.podman.home.packages`, `pname`):
`bat, bottom, coreutils-full, curl, bind (provides dig), eza, fastfetch, fd,
fzf, just, neovim, ripgrep, wget, zoxide, chezmoi` + HM-injected
`shared-mime-info, man-db, hm-session-vars.sh`. The ticket's hint list is
**correct** (dig is `bind`'s `dig`).

### Tier 3 — `nix develop` devshell only

`modules/infra/devshell.nix:46-63` (`devShells.default`, shell name
`lumquat-dev`): `alejandra bws claude-code dig gh git home-manager mcp-nixos
nixd nixfmt nodejs pi-coding-agent secretspec uv worktrunk` (verified by eval).

The ticket's hint list omitted `claude-code`, `nodejs`, `nixfmt`, and `git`
(bws was listed as `secretspec`-adjacent). All four are confirmed present.
`shellHook` exports `IS_NIX_DEVELOP=1` (drives the `(nix-dev)` prompt marker)
and `PI_OFFLINE=1`.

### Other environment facts

- `programs.direnv.enable = true` (`base.nix:27`) — `direnv` is system-wide,
  **but `nix-direnv` is not** (it lives in `cli-build-essentials.nix:22`, and
  `my.cliBuildEssentials` is off for lumquat). So direnv works but has no
  nix-flake integration in podman's home.
- podman's login shell is `pkgs.bash` (`base.nix:18`).
- `my.cliVcsTools` is off for lumquat → **no `gh` in tier 2**; `gh` exists only
  in the devshell (tier 3). This is the central fact for the `gh` decision.

---

## 3. Part C — the join (deliverable)

Tier key: **T1** = system-wide, **T2** = podman `home.packages`, **T3** =
devshell-only, **Absent** = not installed by nix-config at all, **None** =
target belongs to no nix-config tool (shell/chezmoi plumbing itself).

### 3.1 Targets whose tool IS installed (T1/T2/T3)

| Tool | Tier | Managed target(s) | Verdict |
|---|---|---|---|
| git | T1+T3 | `~/.config/git/{config,attributes,ignore}` | correct (T1) |
| nix / nix-command | T1 (nix, determinate) | `~/.config/nix/nix.conf` | correct, but see §4 |
| just | T2 | `~/.justfile` | correct — **hard dependency of nix-config** (§4) |
| bat | T2 | `~/.config/bat/{config,themes/*}` | correct |
| btop | T1 | `~/.config/btop/{btop.conf,themes/*}` | correct |
| fastfetch | T2 | `~/.config/fastfetch/*` | correct |
| neovim | T2 | `~/.config/nvim/**` | correct |
| eza | T1+T2 | — (none) | **gap** (see 3.4) |
| curl | T1+T2 | — | gap (no config expected) |
| wget | T1+T2 | — | gap (no config expected) |
| fd | T2 | — | gap (no config expected) |
| fzf | T2 | — | gap (no config expected) |
| zoxide | T2 | — | gap (no config expected) |
| bottom | T2 | — | gap (no managed config; battery shipped `bottom` but no cfg) |
| coreutils-full | T2 | — | gap/none |
| dig (bind) | T2 | — | gap (no config expected) |
| vim | T1 | `~/.vimrc` | correct |
| secretspec | T1+T3 | `~/.config/secretspec/config.toml` | correct |
| gh | **T3 only** | `~/.config/gh/{config.yml,hosts.yml}` | **tier-3-only target** — devshell still runs on the box (§3.4) |
| worktrunk | **T3 only** | `~/.config/worktrunk/config.toml` | **tier-3-only target** (also §3.4) |
| zmx | T1 | — | gap (no managed config) |
| direnv | T1 | — | gap (no managed config; `nix-direnv` absent) |
| nh | T1 | — | gap (no config) |
| bws | T1+T3 | — | gap (no config) |
| chezmoi | T2 | — | n/a (the harness itself) |
| tailscale | T1 (access module) | — | gap |
| podman | T1 (system) / T2 quadlet | `~/.config/containers/systemd/mealie.container` | correct-ish (see §4) |
| claude-code | T3 only | — (excluded: `.claude` ignored) | consistent |
| pi-coding-agent | T3 only | `~/.pi/**` | **tier-3-only target, plus state** — the map's open `~/.pi` question |

### 3.2 Shell plumbing (None — not a nix-config tool)

| Target | Note |
|---|---|
| `~/.bashrc`, `~/.bash_profile`, `~/.hushlogin` | bash is podman's shell (T2-adjacent: `pkgs.bash` is system). Correct by construction. |
| `~/.config/shell/*.sh` | the shared layer; `devtools.sh`/`shortcuts.sh` inert on headless by template gate |
| `~/.config/bashrc.d/*` | includes dead `starship-gate.sh`, `020-prompt.sh` is live |
| `~/.zshenv` | **zsh entrypoint ships although zsh config is excluded** — dead machinery (see §3.4) |
| `~/.local/bin/*` | personal helper scripts — several reference absent tools (`mac_logout_handler.zsh`, `list-cloudflare-ips`, `setup-bws-keyring.sh`) |
| `~/AGENTS.md` | agent context, not a tool config |
| `~/.config/devenv/config.yaml` | `devenv` is not installed in any tier (`cli-build-essentials` is off for lumquat; the devshell has no `devenv`) → **Absent** |
| `~/.config/zennotes/config.toml` | zennotes is not installed (GUI module off) → **Absent** |
| `~/.config/systemd/user/*` | systemd exists system-wide; `tmux.service` references `tmux` which is **Absent**; `sunset.service` references the sunset script |

### 3.3 Tool-absent targets (wrong by the map's rule)

These managed targets configure tools that nix-config does **not** install on
lumquat in any tier:

- `~/.config/devenv/config.yaml` — `devenv` absent (no tier).
- `~/.config/zennotes/config.toml` — absent.
- `~/.config/systemd/user/tmux.service` — `tmux` absent (and `.config/tmux` is
  itself excluded, so this is the one surviving tmux artefact).
- `~/.config/systemd/user/sunset.service(.timer)` — `sunset`/hyprland desktop
  script; absent.
- `~/.local/bin/mac_logout_handler.zsh` — macOS-only script on a linux host.
- `~/.local/bin/git-prompt-path` — a starship prompt helper; starship is absent on headless, so it is inert machinery.
- `~/.local/bin/list-cloudflare-ips` — ops/personal helper (uses `curl`, present), but scoped to ashebanow's Cloudflare account.
- `~/.local/bin/{extract,git-open,git-st,ssh_hosts,wttr,nerdfont-smoke-test,rename_dot_files.sh}` — verify individually; `wttr` needs network, `nerdfont-smoke-test` is desktop-font related.
- Dead prompt machinery: `~/.config/bashrc.d/starship-gate.sh`,
  `~/.config/shell/starship-nix-gate.sh`, `~/.zshenv`.
- The leaked desktop artefacts from §1.4: `.config/.obsidian`,
  `.config/syncthingtray.ini`, `.config/YouTube Music`, `.config/Code`.
- `~/.pi/**` — pi is **T3-only**; the map already flags this.

### 3.4 Tools with no managed config (gaps, not missing work)

Tier 1–2 tools for which the headless home carries **no** config file. These are
*gaps to decide*, not defects: most are correct to leave unconfigured.

| Tool | Tier | Note |
|---|---|---|
| eza | T1+T2 | eza aliases live in `~/.config/zsh/eza.zsh` — **excluded on headless**, so podman has no eza config at all |
| fzf | T2 | aliases live in `~/.config/shell/productivity.sh` (shipped) — no `FZF_DEFAULT_OPTS` file |
| zoxide | T2 | init lives in `shell/hooks.sh` (shipped) |
| fd | T2 | `FZF_DEFAULT_COMMAND` in `shell/productivity.sh` |
| bottom, btop | T1/T2 | btop has config; bottom none |
| dig, curl, wget, coreutils-full | T1/T2 | no config expected |
| zmx, direnv, nh, bws, secretspec(manifests), tailscale | T1 | no user config shipped; `secretspec/config.toml` IS shipped (one honest gap: it points at a BWS vault) |

**Most important gap:** **`gh` (T3) and `worktrunk` (T3) are devshell-only
tools that still have podman-user config shipped to the box.** The devshell
runs on lumquat (`nix develop`), so these targets are *reachable*, but they are
tier-3-only — the map's rule keys on what nix-config installs at T1/T2, so the
pruning decision on `gh`/`worktrunk` is a judgement call this ticket surfaces
rather than settles. This is the `gh` question BOX-165 Q9b explicitly holds
open.

---

## 4. Part D — system-wide config vs podman-user config

### 4.1 System-wide things that need podman-user config (currently provided or missing)

- **`~/.justfile` is load-bearing for nix-config.** The repo-root `justfile`
  (`nix-config/justfile:35`) does `import "~/.justfile"`. If the pruning pass
  removes it, `just` recipes in the nix-config checkout break. **Keep.**
- **`~/.config/nix/nix.conf`** is the *client-side* config; the daemon-side
  settings live in the flake (`modules/infra/nix/nix.nix`, `caches.nix`). The
  chezmoi file's own header documents that split. `auto-optimise-store = true`
  is set here while the flake does not set it — a client-only setting, so no
  fight today, but worth verifying against Determinate Nix's defaults.
- **`~/.config/containers/systemd/mealie.container`** — a rootless-podman
  quadlet for the podman user. nix-config manages podman system-wide
  (`virtualisation.podman`) but not this user quadlet; no conflict, but the
  quadlet mounts `/srv/mealie` and is otherwise unmanaged by nix-config.
- **direnv**: system-wide program enabled (`base.nix:27`) but no `nix-direnv`
  in podman's home (`cliBuildEssentials` off). If nix-config expects
  `nix develop`/flake support in direnv on lumquat, that is a real missing
  user-level piece.

### 4.2 Overlap / fighting configuration

- **`nix.conf` splits cleanly** but is the closest thing to an overlap: the
  flake owns daemon settings, chezmoi owns client settings, and chezmoi's copy
  sets `extra-experimental-features = nix-command flakes` while the flake sets
  the same at daemon level. Redundant, not conflicting.
- **git identity**: `~/.config/git/config` sets `user.email`/`name` from
  `[data]` (chezmoi), personal-free on headless. nix-config does not set git
  identity. No fight; the map's GitHub-App-for-the-server work is the future
  change here.
- **ssh**: `~/.ssh` is excluded on headless (autorized_keys are provisioned by
  nix-config's `base.nix` instead). No fight, correct split.
- **systemd user units**: chezmoi ships `sunset.service`, `sunset.timer`,
  `tmux.service`; nix-config owns system-level systemd units. The user units
  are for absent tools (§3.3).
- **`gh` credentials**: chezmoi writes `~/.config/gh/hosts.yml` with a personal
  OAuth token (BWS `5a333d5a`) that renders on lumquat because `hm-infra.nix`
  exports the bootstrapped token before apply. nix-config itself does not
  manage gh config. This is the token the map wants to replace with a GitHub
  App identity.

---

## 5. Reproducibility notes

- Part A render + decode: `/tmp/render_ignore.py`, `/tmp/compute_targets.py`
  (scripts are throwaway; the method is described in §1.1 and validated against
  `chezmoi managed` / `chezmoi execute-template`).
- Part B eval commands:
  - `nix eval --json .#nixosConfigurations.lumquat.config.environment.systemPackages --apply 'map (p: p.pname or p.name)'`
  - `nix eval --json .#nixosConfigurations.lumquat.config.home-manager.users.podman.home.packages --apply 'map (p: p.pname or p.name)'`
  - `nix eval --json .#devShells.x86_64-linux.default --apply 's: map (p: p.pname or p.name) s.nativeBuildInputs'`
- Sandbox ignore-pattern check:
  `chezmoi --source ./home --destination ./dest managed` with a minimal
  `home/.chezmoiignore`.
- Both repos were read-only. No tracked file was modified. The only writes are
  this file and the commit on `research/headless-managed-inventory`.

## 6. Sources

- chezmoi source tree: `home/.chezmoiignore.tmpl` (lines 1–89),
  `home/.chezmoi.toml.tmpl` (headless detection), `home/.chezmoiremove`,
  per-directory `.chezmoiignore` files, `home/dot_bashrc.tmpl`,
  `home/private_dot_config/git/config.tmpl`,
  `home/private_dot_config/gh/hosts.yml.tmpl`,
  `home/private_dot_config/nix/nix.conf.tmpl`, `home/dot_justfile.tmpl`.
- nix-config: `modules/features/base.nix:18,27,78-92`,
  `modules/features/cli-tools.nix:12-27`, `modules/features/zmx.nix:15`,
  `modules/infra/hm-infra.nix:18-30`, `modules/infra/devshell.nix:46-63`,
  `modules/infra/nixos-builder.nix`, `modules/infra/nix/{nix,caches}.nix`,
  `hosts/lumquat/configuration.nix`, `justfile:35`, `lib/options-module.nix:131`.
- Prior decisions: BOX-118 map description (BOX-123 inventory decision), BOX-165
  map description (Q9b `gh`, Q15 BWS token, `Not yet specified` for `~/.pi`).
- Prior research: `docs/research/chezmoi-bws-headless.md` §3 (target-path
  matching), `docs/research/home-manager-chezmoi.md` (HM wiring).
