# Code-execution paths in the chezmoi source tree, judged for a headless NixOS host

**Ticket:** [BOX-166](https://linear.app/boxbow/issue/BOX-166/research-every-chezmoiscripts-run_-script-and-run_-attribute-judged-for) — part of wayfinder map BOX-165 (HEADLESS DOTFILES)
**Date:** 2026-09-12 (research pass, chezmoi v2.72.1 from nixpkgs)
**Target machine class:** NixOS server `lumquat`, user `podman`, no desktop, no
Homebrew, no keyring session, none of ashebanow's personal secrets; applied via
`chezmoi apply --force` driven by a `home.activation` entry on every
`nh os switch`.
**Scope:** Every path in the chezmoi source tree that **runs code** on the
target, plus every render-time command invocation, with a keep / gate / exclude
verdict for this machine class. This is a fact-finding document — no pruning
edits were made.

## TL;DR

- **Yes — `chezmoi apply --force` on lumquat currently executes exactly one
  execution path whose non-zero exit aborts the whole apply:**
  `home/dot_pi/agent/extensions/linear/private_credentials.json.tmpl` (target
  `~/.pi/agent/extensions/linear/credentials.json`). It calls
  `output "bws" …` **unguarded**, is **not** covered by any `.chezmoiignore`
  entry, and is **not** gated on `.headless`.
- **The failure is branch-conditional.** `hm-infra.nix` provisions
  `BWS_ACCESS_TOKEN` via `sudo -n cat /var/lib/secrets/bws-access-token || true`
  before applying. If that read succeeds, the template renders and apply is
  clean (verified, exit 0). If it fails — the documented token-less fallback
  path — `bws secret get` exits 1, chezmoi aborts the apply (exit 1), and
  because `hm-infra.nix` runs the apply inside `home.activation`, the failure
  propagates to `nh os switch`.
- **The two `.chezmoiscripts/run_*` scripts are both safe on this host.**
  Neither executes against lumquat: the darwin script is OS-ignored, and the
  linux script renders to an empty file (hostname-gated to `thinkpad`) which
  chezmoi executes but which exits 0. Neither can abort the apply.
- **OS gating of `.chezmoiscripts/{darwin,linux}/**` is complete.** Both
  directories are covered by the `ne .chezmoi.os …` conditionals and no other
  OS tree exists.

## Method

Primary evidence, in order of preference:

- **Empirical sandbox runs** on this machine (chezmoi v2.72.1, nixpkgs) with an
  isolated source dir, destination dir, and chezmoi state, so the real
  `~/.config/chezmoi/chezmoistate.boltdb` and `~` were never touched:
  a copy of `home/` with `[data] headless = true`, `hostname = "lumquat"`, and
  `BWS_ACCESS_TOKEN`/`BW_SESSION` unset. A `bws` shim on `PATH` modelled the
  token-present branch.
- **Repo files** (`home/.chezmoiignore.tmpl`, `home/.chezmoi.toml.tmpl`,
  `home/.chezmoiscripts/**`, every `.tmpl` that invokes a template command
  function).
- **The wiring repo** `/Users/ashebanow/Development/nix/nix-config/main/modules/infra/hm-infra.nix`
  (the `home.activation.chezmoiApply` entry).
- Prior research in this repo: `docs/research/chezmoi-bws-headless.md`
  (failure mode of `output "bws"` with no token; `.chezmoiignore` semantics),
  `docs/research/home-manager-chezmoi.md` (the activation wiring).

## 1. `.chezmoiscripts/**` — every `run_*` script

There are exactly **two** files under `home/.chezmoiscripts/`, one per OS tree.
No `run_once_` scripts exist. No `run_*` script lives outside
`.chezmoiscripts/`.

| Path | Prefix / gate | What it does | Needs on PATH | On lumquat |
|---|---|---|---|---|
| `home/.chezmoiscripts/darwin/run_onchange_after_100-configure-defaults.sh` | `run_onchange_after_`, OS-gated by `.chezmoiignore` (`.chezmoiscripts/darwin/**` when `os != darwin`) | Runs `defaults write …` to set macOS UI/keyboard prefs | `defaults` (macOS) | File is ignored, never rendered or executed |
| `home/.chezmoiscripts/linux/run_onchange_after_100-max-user-watches.sh.tmpl` | `run_onchange_after_`, **hostname-gated in the template body**: the whole file is wrapped in `{{ if eq .chezmoi.hostname "thinkpad" }}` | Appends `fs.inotify.max_user_watches = 524288` to `/etc/sysctl.conf` and runs `sudo sysctl -p` | `grep`, `sudo` (**root**, writes outside `$HOME`) | Renders to an **empty file**; chezmoi executes it, it exits 0 (verified) |

Verdicts:

- `darwin/…configure-defaults.sh` — **keep as-is.** Correctly OS-gated; cannot
  reach a Linux host. (It assumes macOS `defaults`; that is exactly what the
  darwin gate is for.)
- `linux/…max-user-watches.sh.tmpl` — **keep**, but the gating predicate is
  doing load-bearing work that is easy to miss: this is the only script that
  needs **root** and writes **outside `$HOME`**. Gate is correct for lumquat
  (hostname `thinkpad` fails, body empty). If it ever needs to apply to more
  hosts, prefer an explicit `{{ if not .headless }}` alongside the hostname
  check so the sudo/`/etc` behaviour can never land on a headless host.
  **Note:** the empty-render behaviour is verified safe *today*, but it relies
  on the entire script body being inside the `if`. A future line placed outside
  the conditional would execute on lumquat with `sudo`.

## 2. `run_*` attribute as a filename prefix on managed files

Exhaustive `find home -name 'run_*'` returns only the two files above; there
are no `run_onchange_*` / `run_once_*` prefixed *managed files* anywhere in
`home/`. `finding:.chezmoiscripts` is the only home for them.

The other attribute-style filename prefixes present in the tree do **not** run
code:

| Prefix | Example | Executes? |
|---|---|---|
| `executable_` | `home/private_dot_local/bin/executable_ssh_hosts` | No — sets the mode bit only |
| `symlink_` | `home/dot_pi/agent/symlink_settings.json.tmpl` | No — creates a symlink to a source-tree file |
| `private_`, `readonly_` | many | No — permissions only |
| `empty_` | `home/empty_dot_hushlogin` | No — creates an empty file |

No verdict needed beyond **keep** for these; none is an execution path.

## 3. Render-time command execution in templates

`chezmoi apply` evaluates every managed `.tmpl` file and runs any command
invoked by a template function (`output`, `exec`, `bitwardenSecrets`, …). A
non-zero exit from those commands fails template evaluation and **aborts the
whole apply** (`docs/research/chezmoi-bws-headless.md` §2, empirically
verified there and reproduced here).

Every command-invoking template call in `home/`, with its headless disposition:

| Source file | Target | Call | Gate | On lumquat |
|---|---|---|---|---|
| `home/.chezmoi.toml.tmpl` | chezmoi config | `output "scutil" "--get" "ComputerName"` | inside `{{ if eq .chezmoi.os "darwin" }}` | **Not reached** (Linux) — safe |
| `home/dot_pi/agent/extensions/linear/private_credentials.json.tmpl` | `~/.pi/agent/extensions/linear/credentials.json` | `output "bws" "secret" "get" "d3c9dba0-…"` ×2 | **none** | **Renders; aborts apply when no BWS token** |
| `home/private_dot_config/git/config.tmpl` | `~/.config/git/config` | `output "bws" …` (signingkey) | `{{ if not .headless }}` | Not reached — safe |
| `home/private_dot_config/gh/hosts.yml.tmpl` | `~/.config/gh/hosts.yml` | `output "bws" …` ×2 | `{{ if env "BWS_ACCESS_TOKEN" }}` | Guarded — safe token-less |
| `home/private_dot_config/nix/nix.conf.tmpl` | `~/.config/nix/nix.conf` | `output "bws" …` | `{{ if env "BWS_ACCESS_TOKEN" }}` | Guarded — safe token-less |
| `home/private_dot_ssh/*.tmpl` (5 files) | `~/.ssh/*` | `output "bws" …` | `.ssh` in headless ignore | Never evaluated — safe |
| `home/private_dot_hermes/private_config.yaml.tmpl` | `~/.hermes/config.yaml` | `bitwardenSecrets "…"` | `.hermes` in headless ignore | Never evaluated — safe |
| `home/dot_justfile.tmpl` | `~/.justfile` | none (the word "output" appears only in a comment) | n/a | Not an execution path |

The `scutil` call in `home/.chezmoi.toml.tmpl:20` is the only macOS-tool
invocation in the tree; it is correctly darwin-gated, and no
`security`/`osascript`/`launchctl` call appears in any template.

## 4. `.chezmoiignore.tmpl` OS gating of `.chezmoiscripts/{darwin,linux}/**`

The pattern set is complete:

- `{{ if ne .chezmoi.os "darwin" }} .chezmoiscripts/darwin/** {{ end }}`
- `{{ if ne .chezmoi.os "linux" }} .chezmoiscripts/linux/** {{ end }}`
- There is **no** `windows/` directory under `home/.chezmoiscripts/`, so no
  third OS tree needs a gate.

Gotchas already established in `chezmoi-bws-headless.md` and re-confirmed here
by rendering the repo's own files: `.chezmoiignore` patterns match the
**target** path, and `.chezmoiscripts/...` *is* the target path (the
`.chezmoiscripts` directory name is not a chezmoi source attribute), so the
patterns match correctly. Both OS-specific script trees are therefore fully
covered.

**Verdict: keep.** No change needed to the `.chezmoiscripts` gating.

One caveat worth recording: the `headless` ignore block (§ `{{ if .headless }}`)
does **not** reference `.chezmoiscripts` at all, so *if* a future
cross-platform script is added under `.chezmoiscripts/` (not in an OS subtree)
it will run on lumquat unless it is separately gated. Today none exists.

## 5. Desktop / Homebrew / macOS-tool / keyring / Bitwarden assumptions

These are *potential* execution paths; the question is whether any is reachable
on lumquat.

- **Desktop / GUI:** every desktop tree (`.config/hypr`, `.config/niri`,
  `.config/waybar`, …) is under the headless ignore block. Verdict **keep** —
  already gated.
- **Homebrew prefix:** `home/private_dot_config/shell/devtools.sh` (`brew`
  init, `brew --prefix`) is sourced only from `.bashrc`/`.zshrc` under
  `{{ if not .headless }}`. Not a chezmoi *apply* execution path anyway.
  Verdict **keep**.
- **macOS tools (`scutil`, `security`, `osascript`, `launchctl`):**
  `scutil` is darwin-gated (above). `security` appears only inside
  `home/private_dot_local/bin/executable_setup-bws-keyring.sh`, a script file
  that chezmoi merely installs — it is **not run** by apply. Verdict **keep**.
- **Keyring (`secret-tool`):** same file (`executable_setup-bws-keyring.sh`)
  and `home/private_dot_config/shell/secrets.sh`; both install-only / sourced
  by interactive shells. Not run by apply. Verdict **keep**.
- **Bitwarden/BWS session:** the risky one is the **unguarded `output "bws"`**
  covered in §3 — `linear/private_credentials.json.tmpl`. Every other `bws`
  call is either guarded or ignored. Verdict: **gate** the linear template (see
  §7).

## 6. Writes outside `$HOME` / root

The only path that writes outside `$HOME` or needs root is the linux
`max-user-watches` script (`/etc/sysctl.conf`, `sudo`) — hostname-gated to
`thinkpad`, not lumquat. `.chezmoiremove` only removes files under `~`
(`.config/mise/…`, `.local/bin/setup-mise.sh`, `.local/share/nix/…`). No other
path touches `/etc`, `/usr`, or `/var`.

## 7. Verdict table

| Execution path | What it does on lumquat | Verdict | Mechanism |
|---|---|---|---|
| `.chezmoiscripts/darwin/run_onchange_after_100-configure-defaults.sh` | Ignored (not darwin) | **keep** | OS ignore already present |
| `.chezmoiscripts/linux/run_onchange_after_100-max-user-watches.sh.tmpl` | Renders empty; exits 0 | **keep** (optionally add `not .headless`) | hostname gate in template body |
| `.pi/agent/extensions/linear/private_credentials.json.tmpl` | Calls `bws` unguarded → **aborts apply when token absent** | **gate** | `{{ if env "BWS_ACCESS_TOKEN" }}` around the `output` calls, or add `.pi` to the `{{ if .headless }}` ignore block, or `.chezmoiignore` in `home/dot_pi/agent/` |
| `git/config.tmpl` signingkey | Not reached (headless) | **keep** | `{{ if not .headless }}` |
| `gh/hosts.yml.tmpl`, `nix/nix.conf.tmpl` | Guarded | **keep** | `{{ if env "BWS_ACCESS_TOKEN" }}` |
| `.ssh/*.tmpl`, `.hermes/*.tmpl` | Not evaluated | **keep** | headless ignore |
| `~/.config/shell/*.sh`, `executable_*` helpers | Not run by apply (installed/sourced only) | **keep** | n/a |
| `.chezmoiremove` entries | Remove stale `~` files | **keep** | `$HOME`-only |

## 8. Highest-priority finding — the abort path

> **Does `chezmoi apply --force` on lumquat currently execute any script whose
> non-zero exit aborts the whole apply?**

**Yes — but not a `.chezmoiscripts` script. It is a template:**
`home/dot_pi/agent/extensions/linear/private_credentials.json.tmpl`
(→ `~/.pi/agent/extensions/linear/credentials.json`).

- Both `apiKey` fields are filled by `{{ index (output "bws" "secret" "get"
  "d3c9dba0-ea88-4774-bd62-b4a9001c6d9a" | fromJson) "value" }}` with **no
  conditional**.
- The file is **not** in any `.chezmoiignore` (the headless block lists no
  `.pi`; `home/dot_pi/agent/.chezmoiignore` ignores only `editable-*` and
  `git`/`npm`), and `.pi` is not OS-gated.
- **Failure mode:** when `BWS_ACCESS_TOKEN` is empty, `bws secret get` exits 1
  (`Doesn't contain a decryption key` / `Missing access token`), chezmoi wraps
  it as a template execution error and aborts with **exit 1** — reproduced in
  the sandbox:
  `chezmoi: .pi/agent/extensions/linear/credentials.json: … at <output "bws"
  "secret" "get" "d3c9dba0-…">: error calling output: … bws secret get …: exit
  status 1`.
- Because `hm-infra.nix` runs `${chezmoi} apply --force` inside
  `home.activation.chezmoiApply` (a `lib.hm.dag.entryAfter
  ["writeBoundary"]` entry), the non-zero exit fails the activation and
  therefore **fails the whole `nh os switch`**.
- **Branch condition:** `hm-infra.nix` sets
  `export BWS_ACCESS_TOKEN="$(sudo -n cat /var/lib/secrets/bws-access-token
  2>/dev/null || true)"`. If the token read succeeds, the template renders and
  the apply is clean — verified in the sandbox with a `bws` shim (exit 0). The
  abort occurs on the **documented token-less fallback** (`|| true`), which is
  exactly the path the host comment claims is safe ("the headless
  `.chezmoiignore` excludes the personal-secret templates … so apply runs
  token-less"). That claim is currently **false for the linear credentials
  template**: it is the one personal-secret template that is neither ignored
  nor guarded.
- **Isolation proof:** with only `extensions/linear` added to the pi ignore,
  the full headless apply succeeds **exit 0** — i.e. this template is the sole
  abort-causing execution path.

**Neither `run_*` script can cause this abort.** The darwin one never runs on
lumquat, and the linux one executes as an empty script (exit 0).

## 9. Sources

- Empirical (sandbox `/tmp/lum`, chezmoi v2.72.1, isolated source/dest/state):
  headless apply with no token → exit 1 on the linear credentials template;
  with `extensions/linear` ignored → exit 0; with a `bws` shim and
  `BWS_ACCESS_TOKEN` set → exit 0; empty-rendered linux script → exit 0;
  token-less failure text quoted in §8.
- `home/dot_pi/agent/extensions/linear/private_credentials.json.tmpl` (lines
  6, 9 — unguarded `output "bws"`); `home/dot_pi/agent/.chezmoiignore`;
  `home/.chezmoiignore.tmpl` (OS conditionals, headless block);
  `home/.chezmoi.toml.tmpl` (headless detection, darwin `scutil` gate);
  `home/.chezmoiscripts/**`; `home/private_dot_config/git/config.tmpl` (line 85,
  under the `{{ if not .headless }}` gate); `home/private_dot_config/gh/hosts.yml.tmpl` and
  `home/private_dot_config/nix/nix.conf.tmpl` (`env "BWS_ACCESS_TOKEN"` gates).
- `/Users/ashebanow/Development/nix/nix-config/main/modules/infra/hm-infra.nix`
  (the `home.activation.chezmoiApply` entry, `sudo -n cat … || true` token
  provisioning, `apply --force`).
- `docs/research/chezmoi-bws-headless.md` — `output "bws"` failure mode and
  exit code; `.chezmoiignore` prevents template evaluation; target-path
  matching semantics.
- `docs/research/home-manager-chezmoi.md` — `home.activation` runs on every
  `nh os switch`; chezmoi's `init`/`apply --force` non-interactive semantics.
