# BASH_UPGRADE — A mostly-shared zsh/bash configuration

**Status:** **Implemented** on branch `bash-upgrade` (Phases 0–5, 2026-09-01; not yet merged to `main`). Decisions were locked via the wayfinder map (BOX-108) and folded into this doc; it is the spec as built. Deviations from the sketch below are marked in place (env.sh does not chain secrets; 999_secrets.sh stays as the bash secrets entry).
**Scope:** Consolidate the ~900 lines of zsh config (238 `.zshenv` + 265 `paths.zsh` + 366 `zshrc.d/` + rc/profile) and ~110 lines of bash config
that currently exist as two separate universes in this repo into one shared core
plus two small per-shell layers.
**Constraint (hard):** no `if bash … else …` sprawl. The entire design contains
**zero** literal zsh-vs-bash branches — the one candidate (fzf, in `hooks.sh`)
was verified collapsible to a shared substitution (§4.2). Everything else is
either shared verbatim, keyed on a shell _variable_ substituted in one place,
or kept in a per-shell file.

---

## 1. Current state

| Surface           | zsh                                         | bash                                |
| ----------------- | ------------------------------------------- | ----------------------------------- |
| Startup files     | `.zshenv` (238), `.zprofile` (16)           | `.bash_profile` (6)                 |
| Interactive rc    | `.zshrc` + `zshrc.d/` (366 across 13 files) | `.bashrc` (46) + `.bashrc.d/`       |
| PATH machinery    | `~/.local/bin/paths.zsh` (265)              | inline regex-dedupe in `.bashrc`    |
| Secrets (BWS/SSH) | inside `.zshenv` (~160 lines)               | `bashrc.d/999_secrets.sh.tmpl` (60) |

### Already duplicated today (the proven-shareable set)

| Content                | zsh location          | bash location                |
| ---------------------- | --------------------- | ---------------------------- |
| `bling.sh` source      | `dev-tools.zsh`       | `.bashrc`                    |
| `.cargo/env`           | `dev-tools.zsh`       | `.bashrc`                    |
| `wt config shell init` | `version-control.zsh` | `.bashrc`                    |
| `_bws_keyring_token`   | `.zshenv`             | `999_secrets.sh.tmpl` (copy) |
| `_bws_load_ssh_keys`   | `.zshenv`             | `999_secrets.sh.tmpl` (copy) |

The two BWS functions are **byte-identical modulo indentation**, and the bash
copy is a strict subset: it lacks `_bws_refresh_cache` (cache population) and
`_bws_flakehub_login` (determinate-nixd auth) entirely. Today bash can only
_read_ the cache that zsh populates — a latent bug (bash-only session ⇒ stale
or missing cache).

### Why the startup models force extraction, not file-sharing

Bash never reads `.zshenv`. Interactive bash reads `.bashrc`; login bash reads
`.bash_profile` (which here just sources `.bashrc`). So the shared layer has to
be _new files that both entrypoints source_, not "make `.zshenv` shared".

### Where bash actually runs (drives the design)

Interactive bash is a **narrow but real surface** — two cases, both cheap to
cover:

1. **Headless NixOS servers (VPS)** — the primary recurring bash surface. SSH
   login shells are bash by default (easier with VPS providers). Login chain
   `.bash_profile` → `.bashrc` carries the shared layer. Implications:
   - Secrets on these hosts do **not** flow through the shell at all. The
     nix-config bootstrap provisions a root-only token once, out-of-band:
     `just bootstrap-bws <host>` writes `/var/lib/secrets/bws-access-token`
     (mode 0600, root:root); systemd services consume it via
     `LoadCredential=access_token:…` and secretspec (see nix-config
     `SECRET_SYNC.md` — "The BWS bootstrap token (the only local secret)").
     User shells deliberately have **no** BWS token, so the shared secrets
     block goes inert there by design: the Linux `secret-tool` branch of
     `_bws_keyring_token` no-ops (no keyring, returns 1), `_bws_refresh_cache`
     / `_bws_load_ssh_keys` early-return on the empty token — the intended
     fail-safe, not a gap. The `BWS_ACCESS_TOKEN` environment fallback
     (comment already says "for CI/headless") is for machines where _you_
     export it yourself — CI runners, or a dev machine outside macOS.
   - No macOS `path_helper` on Linux → `replay_path_adds` is irrelevant there
     (it is macOS-zsh-only anyway).
2. **`nix develop` on nix-config** (`~/Development/nix/nix-config/main`) — nix
   runs _bash_ by default in dev shells, but this project changes infrequently,
   so this is an occasional, low-stakes surface:
   - Dev-shell bash reads `~/.bashrc` (**verified 2026-09-01**: a bug in a
     `.bashrc`-sourced file surfaced as a syntax error under `nix develop`, so
     the chain is live) → the shared layer runs there too; `hooks.sh`'s
     `command -v` guards naturally wire only tools on the dev env's PATH
     (usually none of starship/fzf/gh → plain bash prompt, same as today).
   - `env.sh` prepends user bins (`~/.local/bin`, `~/.cargo/bin`, …) to PATH.
     In a dev shell that technically puts user bins _above_ the dev env — but
     this is **exactly what `.bashrc` does today** (parity, no regression).
     There is no _built-in_ marker for `nix develop` (`IN_NIX_SHELL` is set
     only by legacy `nix-shell`, not `nix develop`). A nix-config `shellHook`
     (`export IS_NIX_DEVELOP=1`) could provide one, but it is **ruled out of
     scope** for this effort: it is a second-repo change, and the §3.4
     `command -v bws` guard already covers the one real hazard (empty-cache
     overwrite). Revisit only if actually needed — track it in the nix-config
     project, not this map.
   - Edge case worth one line of insurance: if `bws`/`jq` aren't on the
     dev-shell PATH but `BWS_ACCESS_TOKEN` is set, `_bws_refresh_cache` would
     write an **all-empty cache** over a good one. Guarded in §3.4.

**Non-surface: devenv.sh.** `devenv shell` preserves the parent shell rather
than forcing bash, so devenv environments (this repo, and everything else on or
moving to devenv) never add a bash surface — the shared layer simply rides the
parent's existing shell setup. No special handling needed.

---

## 2. Classification: shared vs parallel

Measured across `zshrc.d/` (366 lines), `.zshenv` (238), and `paths.zsh` (265):

| Tier                          | Shareability          | zshrc.d lines  | Notes                                                                         |
| ----------------------------- | --------------------- | -------------- | ----------------------------------------------------------------------------- |
| **T1 zsh-only**               | parallel, stays put   | ~100           | zinit/plugins, compinit, history `setopt`s, eza `-g` globals, zmx assoc-array |
| **T2 same logic, shell word** | shared via `hooks.sh` | ~35 (15 sites) | every `eval "$(tool … zsh)"` line                                             |
| **T3 portable verbatim**      | shared as-is          | ~150           | aliases, exports, simple functions, chezmoi aliases                           |
| **T4 env/secret layer**       | shared via `env.sh`   | (in `.zshenv`) | brew/nix init, PATH adds, BWS/SSH — ~90% portable                             |

Total: roughly **55–60% of the zsh config content** becomes shareable; the
remaining ~40% stays parallel but is small and mostly one-liners.

---

## 3. The secrets deep-dive (what the diff + sandbox proved)

This section is the answer to "what do we lose by starting from the zsh version?"
**Answer: nothing.** The evidence:

### 3.1 The zsh block is the superset, and it already runs in bash

- `_bws_keyring_token`, `_bws_load_ssh_keys`: identical in both files (whitespace only).
- The "zsh-only-looking" machinery — `zmodload zsh/stat`/`zstat`, `(( … ))`
  arithmetic, atomic `{ … } > tmp && mv`, the flakehub sentinel — is **already
  bash-compatible**. The `zstat` branch simply never fires in bash; the existing
  BSD/GNU `stat` fallbacks take over. `local`, `[[ … ]]`, `&>/dev/null`, `$( )`
  are all fine in both.
- `bash -n` and `zsh -n` both pass on the unmodified zsh secrets block.

### 3.2 The one required portability fix: `[[ -o interactive ]]`

This is the only construct in the zsh block that is **broken in bash**:

- `set: interactive: invalid option name` — bash has no `interactive` option
  (only `interactive-comments`), so `[[ -o interactive ]]` is **always false in
  bash**, even in a genuinely interactive shell (`$-` = `himBHs`).
- Consequence if left unpatched: `_bws_refresh_cache` would **silently never
  run in bash** — the cache would never populate.
- Fix is a 3-line POSIX shim (valid in zsh, bash, and even `sh`), used 3× in
  place of `[[ -o interactive ]]`:

```sh
is_interactive() { case $- in *i*) return 0;; *) return 1;; esac; }
```

### 3.3 Sandbox verification (PTY-driven, fake `bws` counting calls)

| Scenario                               | Source-time refresh        | Explicit refresh (fresh cache) | Refresh after `touch .zshenv` |
| -------------------------------------- | -------------------------- | ------------------------------ | ----------------------------- |
| Original block in interactive **bash** | **0 calls — broken guard** | 0                              | 0                             |
| Patched block in interactive **bash**  | 9 calls, cache written     | skipped ✓                      | +9 ✓                          |
| Patched block in interactive **zsh**   | 9 calls, cache written     | —                              | +9 ✓ (no regression)          |

Cache files produced by bash and zsh were **byte-identical** (`diff` clean).
The harness lives at `/tmp/bws-test/` (`drive.py`, `secrets.sh`,
`secrets-patched.sh`) for reproduction.

### 3.4 Resulting shared file shape

`~/.config/shell/secrets.sh` = zsh block verbatim + `is_interactive()` shim,
with the mtime invalidation reference changed from `~/.zshenv` to the shared
file itself (so `chezmoi apply` to the shared file still invalidates). Sourced
from `.zshenv` (where the block sits today) and from
`~/.config/bashrc.d/999_secrets.sh` (which shrinks to a single `source`
line). Do **not** "clean up" the `zmodload`/`zstat` chain while porting —
it is what protects macOS+nix from GNU-stat shadowing.

**One deliberate additive change** (protects both shells equally, changes no
working behavior): guard `_bws_refresh_cache` with
`command -v bws >/dev/null 2>&1 || return 0` before any fetch. Prevents writing
an all-empty cache over a good one when `bws` isn't on PATH (the narrow §1
`nix develop` edge case). `command -v jq` optional as a sibling guard. This
mirrors the existing `command -v determinate-nixd` guard pattern in the same
file.

Known quirk (pre-existing, not a regression): mtime invalidation has 1-second
granularity — a `chezmoi apply` landing in the same second as cache generation
won't invalidate. Same behavior in zsh today.

---

## 4. Proposed target layout

```
home/
  dot_bash_profile                        # unchanged (sources .bashrc)
  dot_bashrc                              # shrinks to entrypoint (~15 lines)
  private_dot_zshenv.tmpl                 # keeps only zsh-preamble + source lines
  private_dot_config/
    bashrc.d/                             # moved from dot_bashrc.d (target ~/.config/bashrc.d)
      010_history.sh                      # NEW: bash history mapping (see §6)
      999_secrets.sh.tmpl                 # shrinks to: source ~/.config/shell/secrets.sh
    shell/                                # NEW shared root (chezmoi: private_dot_config/shell)
      env.sh                              # exports, brew/nix init, add_to_path (POSIX), sources secrets.sh
      secrets.sh                          # BWS/SSH block + is_interactive shim (zsh verbatim)
      rc.sh                               # T3 portable aliases/functions (moved from zshrc.d)
      hooks.sh                            # T2 tool-init wiring, keyed on $_SHELL_NAME
    zsh/
      dot_zprofile                        # unchanged (replay_path_adds)
      dot_zshrc.tmpl                      # entrypoint: set _SHELL_NAME, source shared, then zshrc.d
      zshrc.d/                            # T1 zsh-only files stay here (zinit, completions, history,
                                          #   eza -g globals, zmx assoc-array bits)
      paths.zsh                           # moved from ~/.local/bin (zsh-only replay machinery;
                                          #   everything zsh now lives under $ZDOTDIR)
  private_dot_local/bin/                  # executables only (paths.zsh no longer lives here)
```

**Layout notes (from review):**

- `bashrc.d` moves to `~/.config/bashrc.d/` (chezmoi `private_dot_config/bashrc.d`).
  Bash has no native `$XDG_CONFIG_HOME` discovery for rc dirs — this works
  only because the `.bashrc` entrypoint loops over the directory explicitly;
  non-interactive bash is unaffected (same as today). **Decided (2026-09-01):**
  the one non-managed file, `~/.bashrc.d/001_bob_vim.sh` (a bob nvim
  version-manager bash-completion generator), is **dropped** — bob is obsolete
  on nix. No legacy `~/.bashrc.d` fallback is needed: the entrypoint loops only
  `~/.config/bashrc.d/*`. (Verified: the file exists on this machine;
  `~/.config/bashrc.d` is currently empty/absent.)
- `paths.zsh` moves to `~/.config/zsh/paths.zsh` (chezmoi
  `private_dot_config/zsh/paths.zsh`): it is zsh-only, sourced by `.zshenv`,
  and not an executable, so it never needed to live in `bin/` — this puts all
  zsh machinery under `$ZDOTDIR`. The `.zshenv` source line becomes
  `source "$ZDOTDIR/paths.zsh"`. (Verified: the only reference in this repo
  is `.zshenv`; no nix-config references.)

### 4.1 `env.sh` — the shared environment

Sourced by `.zshenv` (every zsh) and `.bashrc` (interactive bash).
Idempotent via a `_ENV_SH_SOURCED` guard (same pattern `paths.zsh` uses).

```sh
# ~/.config/shell/env.sh  (POSIX; runs under zsh and bash)
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export EDITOR=nvim
export DOTFILES=$HOME/.local/share/chezmoi
export BUN_INSTALL="$HOME/.bun"
export PERSONAL_WIKI="$HOME/personal_wiki"
export LITELLM_BASE_URL="https://litellm.fluffy-walleye.ts.net"

# Homebrew init (portable eval; plain-echo warning — see §7)
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -x /opt/homebrew/bin/brew ]; then eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Nix init … (unchanged, portable)

# add_to_path: define only if paths.zsh hasn't already (zsh gets the
# replay-recording version; bash gets this POSIX one). No shell branching.
if ! command -v add_to_path >/dev/null 2>&1; then
  add_to_path() {
    local target="" d
    for arg in "$@"; do case "$arg" in -d|--debug) ;; *) target="$arg";; esac; done
    [ -n "$target" ] || { echo "Usage: add_to_path [-d|--debug] <dir>" >&2; return 1; }
    d=$(eval echo "$target")
    [ -d "$d" ] || return 1
    case ":$PATH:" in *":$d:"*) return 0 ;; esac
    export PATH="$d:$PATH"
  }
fi

# PATH adds (the current ~/.zshenv "Path Management" block, unchanged calls) …
add_to_path "$(brew --prefix postgresql@17)/bin"
add_to_path "$BUN_INSTALL/bin"
# … etc — replaces .bashrc's inline dedupe AND .zshenv's add_to_path calls

# NOTE: secrets are NOT chained here — sourcing secrets.sh from both env.sh
# and 999_secrets.sh would double-load it. Each entrypoint sources secrets
# exactly once: .zshenv (zsh) and ~/.config/bashrc.d/999_secrets.sh (bash).
```

**Why the `command -v add_to_path` guard instead of a shell check:** it's a
feature probe, not a bash-vs-zsh branch. `.zshenv` sources `paths.zsh` first
so zsh keeps the battle-tested recording version; bash gets the simple POSIX
one. Bash doesn't need the replay machinery at all — see §6.

### 4.2 `hooks.sh` — the single home for tool-init wiring

The abstraction: each rc entrypoint sets `_SHELL_NAME` **once**; `hooks.sh`
substitutes it. Tools are keyed by _tool_, never by shell.

```sh
# ~/.config/shell/hooks.sh — sourced by both .bashrc and .zshrc
: "${_SHELL_NAME:=${SHELL##*/}}"   # fallback only; entrypoints set it explicitly

command -v direnv           && eval "$(direnv hook "$_SHELL_NAME")"
command -v starship         && eval "$(starship init "$_SHELL_NAME")"
command -v tv               && eval "$(tv init "$_SHELL_NAME")"
command -v gh               && eval "$(gh completion -s "$_SHELL_NAME")"
command -v uv               && eval "$(uv generate-shell-completion "$_SHELL_NAME")"
command -v uvx              && eval "$(uvx --generate-shell-completion "$_SHELL_NAME")"
command -v devbox           && eval "$(devbox completion "$_SHELL_NAME")"
command -v determinate-nixd && eval "$(determinate-nixd completion "$_SHELL_NAME")"
command -v devenv           && eval "$(devenv hook "$_SHELL_NAME")"
command -v tailscale        && eval "$(tailscale completion "$_SHELL_NAME")"
command -v wt               && eval "$(command wt config shell init "$_SHELL_NAME")"
command -v zmx              && eval "$(zmx completions "$_SHELL_NAME")"
command -v jj               && eval "$(COMPLETE="$_SHELL_NAME" jj)"
command -v thefuck          && eval "$(thefuck --alias)"   # same for both shells

command -v fzf && eval "$(fzf --$_SHELL_NAME)"   # zero shell branches — PTY-verified (fzf 0.74.3)
```

Notes:

- This collapses **~15 call sites spread across 6 zshrc.d files + `.bashrc`**
  into one file. `.bashrc`'s existing `wt config shell init bash` line disappears.
- All 16 tool lines verified for both shells (audit 2026-09-01:
  `docs/research/hooks-bash-audit.md`).
- `gh copilot alias` guard **corrected by the audit**: the old zshrc.d guard was
  inverted (eval'd when the gh-copilot extension was _absent_) and spammed
  stderr when the Copilot CLI wasn't installed. Use:
  `command -v gh && gh copilot --version >/dev/null 2>&1 && eval "$(gh copilot alias -- "$_SHELL_NAME")"`
- The fzf line: `eval "$(fzf --zsh)"` is **PTY-verified byte-equivalent** to
  `source <(fzf --zsh)` in interactive zsh (fzf 0.74.3 / zsh 5.9.2 harness —
  `docs/research/fzf-eval-test.md`), so the
  line is the shared substitution `command -v fzf && eval "$(fzf --$_SHELL_NAME)"`
  — **zero shell branches anywhere**. Caveat: equivalence is per-fzf-version;
  re-run the harness if fzf's generated script ever starts emitting
  `$0`/`zsh_eval_context`/top-level `return`.

### 4.3 `rc.sh` — portable aliases/functions (T3, moved verbatim)

`aliases.zsh` (28 lines) + `chezmoi.zsh` (16) + the portable halves of
`editing.zsh`, `eza.zsh`, `jj.zsh`, `dev-tools.zsh`, `system.zsh.tmpl`,
`utility.zsh`, plus `bling.sh`/`.cargo/env` (deduped from `.bashrc`).
**Decided (2026-09-01):** keep the darwin `pinentry` conditional — `rc.sh`
becomes `rc.sh.tmpl` (per-OS split rejected). `cdzsh` → **`cdshell`** (shared
rc). eza `-g` globals: bash gets equivalent **normal aliases where possible,
functions for the rest**, defined in `rc.sh`.

### 4.4 Entrypoints

```zsh
# dot_zshrc.tmpl (zsh)
export _SHELL_NAME=zsh
source ~/.config/shell/rc.sh
for config_file ($ZDOTDIR/zshrc.d/*.zsh(N)); do source $config_file; done
source ~/.config/shell/hooks.sh      # after zshrc.d: compinit (01) must precede compdef calls
# … zcompile block unchanged
```

```bash
# dot_bashrc (bash)
[ -f /etc/bashrc ] && . /etc/bashrc
export _SHELL_NAME=bash
source ~/.config/shell/env.sh
source ~/.config/shell/rc.sh
for rc in ~/.config/bashrc.d/*; do [ -f "$rc" ] && . "$rc"; done; unset rc   # legacy ~/.bashrc.d fallback per §4 layout notes
source ~/.config/shell/hooks.sh
```

`dot_zshrc` sources `rc.sh` before `zshrc.d` and `hooks.sh` **after** it, so
`01-completions.zsh` (compinit) still precedes the compdef-driving tool evals.

---

## 5. What we deliberately do NOT share

| Piece                                         | Why it stays parallel                                                        |
| --------------------------------------------- | ---------------------------------------------------------------------------- |
| `00-zinit.zsh` (plugins, syntax highlighting) | no bash analogue (would need ble.sh)                                         |
| `01-completions.zsh` (compinit/fpath)         | bash completions are a different mechanism                                   |
| `history.zsh` `setopt`s                       | zsh-only — but maps 1:1 to bash (§6)                                         |
| `eza.zsh` `alias -g` globals (9 lines)        | no bash global-alias concept                                                 |
| `zmx.zsh` assoc-array lookup                  | zsh syntax; replaceable by a portable `case` function (§6)                   |
| `paths.zsh` replay machinery                  | macOS zsh-only need (§6); moved under `$ZDOTDIR` (`~/.config/zsh/paths.zsh`) |
| `dot_zprofile` (replay)                       | zsh-only startup file                                                        |

The spirit: a handful of small, boring per-shell files — not a framework.
No plugin system, no source-tracking, no dispatch layer.

---

## 6. Bash-side equivalents (small parallel ports)

| zsh                   | bash                                                                                                                                     | Notes                                                                                                                                                                                               |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `history.zsh` setopts | `~/.config/bashrc.d/010_history.sh`: `HISTFILE`, `HISTSIZE`, `HISTFILESIZE`, `HISTCONTROL=ignoredups:ignorespace`, `shopt -s histappend` | 1:1 concept map, ~8 lines                                                                                                                                                                           |
| `replay_path_adds`    | **not needed**                                                                                                                           | macOS `path_helper` runs _before_ `~/.bash_profile` in bash, so user prepends already win; Linux has no path_helper. The replay exists only because `/etc/zprofile` runs _after_ `~/.zshenv` in zsh |
| zmx host-name map     | portable `case` function in `rc.sh`                                                                                                      | `ZMX_SESSION_PREFIX="$(case $(hostname -s) in miraclemax) echo mmax;; … esac)."` — no assoc array needed                                                                                            |
| completions           | come from `hooks.sh` evals (gh, uv, devbox, tailscale, jj, wt, fzf all emit bash completions)                                            | bash-completion package itself optional/out of scope                                                                                                                                                |

---

## 7. Risks & mitigations

| Risk                                                                                     | Mitigation                                                                                                                                                                                                                                                                                                                             |
| ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **zsh macOS replay regression** (path_helper ordering)                                   | `paths.zsh` unchanged (only its path moves to `~/.config/zsh/`); `.zshenv` keeps sourcing it _before_ `env.sh`; verify with a login zsh on macOS                                                                                                                                                                                       |
| **`add_to_path` override trap** — `env.sh` clobbering the zsh recording version          | the `command -v add_to_path` guard + fixed source order (paths.zsh first)                                                                                                                                                                                                                                                              |
| `[[ -o interactive ]]` landmine silently killing cache refresh in bash                   | `is_interactive()` shim (verified in sandbox, both shells, no zsh regression)                                                                                                                                                                                                                                                          |
| Shared `env.sh` in non-interactive zsh (every zsh reads `.zshenv`)                       | secrets self-guard via `is_interactive`; brew/nix eval is idempotent (already runs for every zsh today)                                                                                                                                                                                                                                |
| `export SHELL=$(which zsh)` is zsh-intent                                                | stays in `.zshenv` preamble, NOT in `env.sh`                                                                                                                                                                                                                                                                                           |
| `ZDOTDIR` must be set before zsh looks up rc files                                       | stays in `.zshenv` preamble ahead of all sources                                                                                                                                                                                                                                                                                       |
| `print -P` colored brew warning (zsh-only)                                               | `env.sh` uses a plain `echo` warning — deliberate cosmetic downgrade; alternative: keep the warning in `.zshenv` and let `env.sh` stay silent                                                                                                                                                                                          |
| chezmoi template conditional (darwin `pinentry`)                                         | **decided**: keep the conditional → `rc.sh` becomes `rc.sh.tmpl` (§4.3)                                                                                                                                                                                                                                                                |
| **EDITOR drift** (`nvim` in zsh vs `vim` in bash)                                        | resolved by the shared export — pick one (proposal: `nvim`)                                                                                                                                                                                                                                                                            |
| `bashrc.d` contained a non-managed file (`001_bob_vim.sh`)                               | **decided**: dropped — bob (nvim version manager) is obsolete on nix; the entrypoint loops only `~/.config/bashrc.d/*`, no legacy fallback (§4 layout notes)                                                                                                                                                                           |
| Same-second mtime granularity on cache invalidation                                      | pre-existing zsh behavior; document, don't fix in this change                                                                                                                                                                                                                                                                          |
| `bws`/`jq` missing from PATH (rare: `nix develop` on nix-config) → all-empty cache write | the `command -v bws` guard in `secrets.sh` (§3.4); empty cache never written, stale good cache survives                                                                                                                                                                                                                                |
| `env.sh` prepends user bins in `nix develop` shells (shadowing dev-env bins)             | parity with today's `.bashrc`; narrow, infrequent surface — accepted. A nix-config `shellHook` marker (`IS_NIX_DEVELOP`) would enable a future opt-out but is **out of scope** (§1); the §3.4 `command -v bws` guard covers the one real hazard                                                                                        |
| Headless servers: no GUI keyring                                                         | `secret-tool` branch no-ops; on nix-config hosts the bootstrap token is root-only and consumed by systemd (`LoadCredential`), so shells are intentionally token-less and the secrets block goes inert — the intended fail-safe. `BWS_ACCESS_TOKEN` env fallback is for CI/dev machines that export it. Verify in server checklist (§9) |
| Shared files land on PATH (`~/.config/shell/` is not on PATH — good)                     | keep `secrets.sh` non-executable like `paths.zsh`                                                                                                                                                                                                                                                                                      |

---

## 8. Migration plan (phased, each phase independently shippable)

**Status (2026-09-01): Phases 0–5 implemented on `bash-upgrade`, verified live.**
Phase 0 = baseline doc; Phase 1 = secrets; Phase 2 = env; Phase 3 = rc/hooks;
Phase 4 = bashrc.d move + bash history; Phase 5 = portable zmx. Machine
cleanups done alongside: dropped `001_bob_vim.sh` (obsolete on nix) and the
unmanaged stale `completion.zsh` (zsh-autocomplete-era duplicate compinit),
both backed up under `/tmp/bash-upgrade-baseline/removed/`.

1. **Phase 0 — baseline:** feature branch; `chezmoi diff` snapshot; record
   current zsh startup time.
2. **Phase 1 — secrets only (highest value, lowest risk):** create
   `shell/secrets.sh` (zsh block verbatim + `is_interactive` shim + mtime ref);
   `.zshenv` sources it; `999_secrets.sh.tmpl` shrinks to a `source` line.
   Verify: cache populates from bash alone; zsh behavior identical.
3. **Phase 2 — shared env:** `shell/env.sh` (exports, brew/nix, POSIX
   `add_to_path`, PATH adds); `.zshenv` sources it after `paths.zsh`; `.bashrc`
   sources it. Verify PATH order in both, macOS replay still intact.
4. **Phase 3 — portable content + hooks:** `shell/rc.sh` + `shell/hooks.sh`;
   move T3 files out of `zshrc.d`; wire both entrypoints. Verify no duplicate
   definitions, alias parity, completion ordering.
5. **Phase 4 — bash parallels:** `010_history.sh`, `.bashrc` cleanup, eza `-g`
   bash equivalents (**decided**), `cdzsh`→`cdshell` (**decided**), apply
   `EDITOR=nvim` (**decided**).
6. **Phase 5 — optional polish:** portable zmx function. (fzf special-case:
   **done** — zero branches, §4.2. `rc.sh.tmpl`: **decided** — keep the
   conditional, §4.3.)

## 9. Acceptance checklist

- [ ] `zsh` interactive: prompt/plugins/completions unchanged; macOS login PATH
      order intact (replay still fires); secrets cache refreshes; flakehub
      login runs; ssh keys load.
- [ ] `bash` interactive: hooks fire (starship, fzf, gh, uv, …); **cache
      self-refreshes without zsh ever having run**; keys load; PATH correct.
- [ ] **`nix develop` (nix-config):** confirm dev-shell bash reads `~/.bashrc`;
      shared layer loads; no empty-cache write when `bws` is off PATH; user-bin
      prepends match today's behavior.
- [ ] **devenv shell (this repo):** confirms parent shell is preserved (zsh in,
      zsh out); no new bash surface appears.
- [ ] **Headless NixOS server:** SSH login → `.bash_profile` → `.bashrc` chain
      loads shared layer; secrets no-op gracefully (no token, no keyring —
      services get secrets via `LoadCredential`, not the shell); no error
      spam; `BWS_ACCESS_TOKEN` env-var path verified on a CI runner instead.
- [ ] Non-interactive `zsh -c` / `bash -c`: env vars + PATH correct; **no**
      network calls from secrets (guards hold).
- [ ] `chezmoi diff` shows only intended moves; `chezmoi apply` idempotent;
      re-sourcing either rc twice is harmless.
- [ ] zsh startup time not regressed (zinit still lazy-loads).
- [ ] `grep -rn "bash" zshrc.d/` and vice-versa: no cross-shell conditionals
      crept in — zero allowed; the fzf line is now a shared substitution (§4.2).

## 10. Open questions

(Answered during review: interactive bash runs on headless NixOS servers and —
narrowly — `nix develop` on nix-config; devenv preserves the parent shell and
adds no bash surface. See §1. The shared layer is justified.)

1. ~~Do you want bash parity for zinit/syntax-highlighting (ble.sh)?~~
   **Answered (2026-09-01): no — ruled out of scope.** Bash stays lean, no
   plugin manager. (Linear: Bash plugin parity (ble.sh))
2. ~~`EDITOR`: `nvim` everywhere or `vim` stays in bash?~~
   **Answered (2026-09-01): `nvim` everywhere** via the shared `env.sh`.
   (Linear: EDITOR: nvim everywhere)
3. ~~Should `hooks.sh` keep the explicit per-tool lines (§4.2) or become a
   data table?~~
   **Answered (2026-09-01): keep explicit lines** — the audit confirmed the
   rows genuinely differ in guards and argument shapes; a table would fight
   reality. (Linear: hooks.sh: explicit lines vs data table)
4. ~~**Future direction (non-blocking):** secretspec…~~
   **Confirmed out of scope (2026-09-01):** this repo stays on chezmoi's
   native BWS integration; the cache in `secrets.sh` is permanent
   infrastructure. Revisit only if secretspec gains chezmoi support and this
   repo migrates.
