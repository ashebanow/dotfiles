# BASH_UPGRADE — A mostly-shared zsh/bash configuration

**Status:** Proposal for review. Nothing here is implemented yet.
**Scope:** Consolidate the ~900 lines of zsh config (238 `.zshenv` + 265 `paths.zsh` + 366 `zshrc.d/` + rc/profile) and ~110 lines of bash config
that currently exist as two separate universes in this repo into one shared core
plus two small per-shell layers.
**Constraint (hard):** no `if bash … else …` sprawl. The entire design contains
exactly **one** literal zsh-vs-bash branch, confined to a single line (fzf) in
`hooks.sh`. Everything else is either shared verbatim, keyed on a shell *variable*
substituted in one place, or kept in a per-shell file.

---

## 1. Current state

| Surface | zsh | bash |
|---|---|---|
| Startup files | `.zshenv` (238), `.zprofile` (16) | `.bash_profile` (6) |
| Interactive rc | `.zshrc` + `zshrc.d/` (366 across 13 files) | `.bashrc` (46) + `.bashrc.d/` |
| PATH machinery | `~/.local/bin/paths.zsh` (265) | inline regex-dedupe in `.bashrc` |
| Secrets (BWS/SSH) | inside `.zshenv` (~160 lines) | `bashrc.d/999_secrets.sh.tmpl` (60) |

### Already duplicated today (the proven-shareable set)

| Content | zsh location | bash location |
|---|---|---|
| `bling.sh` source | `dev-tools.zsh` | `.bashrc` |
| `.cargo/env` | `dev-tools.zsh` | `.bashrc` |
| `wt config shell init` | `version-control.zsh` | `.bashrc` |
| `_bws_keyring_token` | `.zshenv` | `999_secrets.sh.tmpl` (copy) |
| `_bws_load_ssh_keys` | `.zshenv` | `999_secrets.sh.tmpl` (copy) |

The two BWS functions are **byte-identical modulo indentation**, and the bash
copy is a strict subset: it lacks `_bws_refresh_cache` (cache population) and
`_bws_flakehub_login` (determinate-nixd auth) entirely. Today bash can only
*read* the cache that zsh populates — a latent bug (bash-only session ⇒ stale
or missing cache).

### Why the startup models force extraction, not file-sharing

Bash never reads `.zshenv`. Interactive bash reads `.bashrc`; login bash reads
`.bash_profile` (which here just sources `.bashrc`). So the shared layer has to
be *new files that both entrypoints source*, not "make `.zshenv` shared".

### Where bash actually runs (drives the design)

Interactive bash is a **narrow but real surface** — two cases, both cheap to
cover:

1. **Headless NixOS servers (VPS)** — the primary recurring bash surface. SSH
   login shells are bash by default (easier with VPS providers). Login chain
   `.bash_profile` → `.bashrc` carries the shared layer. Implications:
   - No GUI keyring daemon: the Linux `secret-tool` branch of
     `_bws_keyring_token` no-ops gracefully (returns 1); the designed fallback
     is `BWS_ACCESS_TOKEN` in the environment (comment already says "for
     CI/headless"). Cache file still works when present.
   - No macOS `path_helper` on Linux → `replay_path_adds` is irrelevant there
     (it is macOS-zsh-only anyway).
2. **`nix develop` on nix-config** (`~/Development/nix/nix-config/main`) — nix
   runs *bash* by default in dev shells, but this project changes infrequently,
   so this is an occasional, low-stakes surface:
   - Dev-shell bash reads `~/.bashrc` (verify on first use) → the shared layer
     runs there too; `hooks.sh`'s `command -v` guards naturally wire only tools
     on the dev env's PATH (usually none of starship/fzf/gh → plain bash
     prompt, same as today).
   - `env.sh` prepends user bins (`~/.local/bin`, `~/.cargo/bin`, …) to PATH.
     In a dev shell that technically puts user bins *above* the dev env — but
     this is **exactly what `.bashrc` does today** (parity, no regression), and
     there is no clean marker to detect "inside nix develop" (`IN_NIX_SHELL` is
     set only by legacy `nix-shell`, not `nix develop`). Accepted as-is.
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

| Tier | Shareability | zshrc.d lines | Notes |
|---|---|---|---|
| **T1 zsh-only** | parallel, stays put | ~100 | zinit/plugins, compinit, history `setopt`s, eza `-g` globals, zmx assoc-array |
| **T2 same logic, shell word** | shared via `hooks.sh` | ~35 (15 sites) | every `eval "$(tool … zsh)"` line |
| **T3 portable verbatim** | shared as-is | ~150 | aliases, exports, simple functions, chezmoi aliases |
| **T4 env/secret layer** | shared via `env.sh` | (in `.zshenv`) | brew/nix init, PATH adds, BWS/SSH — ~90% portable |

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

| Scenario | Source-time refresh | Explicit refresh (fresh cache) | Refresh after `touch .zshenv` |
|---|---|---|---|
| Original block in interactive **bash** | **0 calls — broken guard** | 0 | 0 |
| Patched block in interactive **bash** | 9 calls, cache written | skipped ✓ | +9 ✓ |
| Patched block in interactive **zsh** | 9 calls, cache written | — | +9 ✓ (no regression) |

Cache files produced by bash and zsh were **byte-identical** (`diff` clean).
The harness lives at `/tmp/bws-test/` (`drive.py`, `secrets.sh`,
`secrets-patched.sh`) for reproduction.

### 3.4 Resulting shared file shape

`~/.config/shell/secrets.sh` = zsh block verbatim + `is_interactive()` shim,
with the mtime invalidation reference changed from `~/.zshenv` to the shared
file itself (so `chezmoi apply` to the shared file still invalidates). Sourced
from `.zshenv` (where the block sits today) and from `bashrc.d/999_secrets.sh`
(which shrinks to a single `source` line). Do **not** "clean up" the
`zmodload`/`zstat` chain while porting — it is what protects macOS+nix from
GNU-stat shadowing.

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
  dot_bashrc.d/
    010_history.sh                        # NEW: bash history mapping (see §6)
    999_secrets.sh.tmpl                   # shrinks to: source ~/.config/shell/secrets.sh
  private_dot_zshenv.tmpl                 # keeps only zsh-preamble + source lines
  private_dot_config/
    zsh/
      dot_zprofile                        # unchanged (replay_path_adds + orbstack)
      dot_zshrc.tmpl                      # entrypoint: set _SHELL_NAME, source shared, then zshrc.d
      zshrc.d/                            # T1 zsh-only files stay here (zinit, completions, history,
                                          #   eza -g globals, zmx assoc-array bits)
    shell/                                # NEW shared root (chezmoi: private_dot_config/shell)
      env.sh                              # exports, brew/nix init, add_to_path (POSIX), sources secrets.sh
      secrets.sh                          # BWS/SSH block + is_interactive shim (zsh verbatim)
      rc.sh                               # T3 portable aliases/functions (moved from zshrc.d)
      hooks.sh                            # T2 tool-init wiring, keyed on $_SHELL_NAME
  private_dot_local/bin/
    paths.zsh                             # unchanged, zsh-only (replay machinery)
```

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

# Secrets (shared, §3)
source ~/.config/shell/secrets.sh
```

**Why the `command -v add_to_path` guard instead of a shell check:** it's a
feature probe, not a bash-vs-zsh branch. `.zshenv` sources `paths.zsh` first
so zsh keeps the battle-tested recording version; bash gets the simple POSIX
one. Bash doesn't need the replay machinery at all — see §6.

### 4.2 `hooks.sh` — the single home for tool-init wiring

The abstraction: each rc entrypoint sets `_SHELL_NAME` **once**; `hooks.sh`
substitutes it. Tools are keyed by *tool*, never by shell.

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

# The single structural special case in the whole design (fzf: source vs eval):
command -v fzf && { [ "$_SHELL_NAME" = zsh ] && source <(fzf --zsh) || eval "$(fzf --bash)"; }
```

Notes:
- This collapses **~15 call sites spread across 6 zshrc.d files + `.bashrc`**
  into one file. `.bashrc`'s existing `wt config shell init bash` line disappears.
- `gh copilot alias -- $_SHELL_NAME` keeps its extension-existence guard (moves
  in here with it).
- If `eval "$(fzf --zsh)"` proves fine in zsh (it should — eval of the same
  text), the fzf special-case can be deleted entirely, leaving zero shell
  branches anywhere.

### 4.3 `rc.sh` — portable aliases/functions (T3, moved verbatim)

`aliases.zsh` (28 lines) + `chezmoi.zsh` (16) + the portable halves of
`editing.zsh`, `eza.zsh`, `jj.zsh`, `dev-tools.zsh`, `system.zsh.tmpl`,
`utility.zsh`, plus `bling.sh`/`.cargo/env` (deduped from `.bashrc`).
Requires a `.tmpl` suffix if it keeps the darwin `pinentry` conditional —
or move that alias to a per-OS spot. `cdzsh` alias should become `cdshell`.

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
for rc in ~/.bashrc.d/*; do [ -f "$rc" ] && . "$rc"; done; unset rc
source ~/.config/shell/hooks.sh
```

`dot_zshrc` sources `rc.sh` before `zshrc.d` and `hooks.sh` **after** it, so
`01-completions.zsh` (compinit) still precedes the compdef-driving tool evals.

---

## 5. What we deliberately do NOT share

| Piece | Why it stays parallel |
|---|---|
| `00-zinit.zsh` (plugins, syntax highlighting) | no bash analogue (would need ble.sh) |
| `01-completions.zsh` (compinit/fpath) | bash completions are a different mechanism |
| `history.zsh` `setopt`s | zsh-only — but maps 1:1 to bash (§6) |
| `eza.zsh` `alias -g` globals (9 lines) | no bash global-alias concept |
| `zmx.zsh` assoc-array lookup | zsh syntax; replaceable by a portable `case` function (§6) |
| `paths.zsh` replay machinery | macOS zsh-only need (§6) |
| `dot_zprofile` (replay + orbstack) | zsh-only startup file |

The spirit: a handful of small, boring per-shell files — not a framework.
No plugin system, no source-tracking, no dispatch layer.

---

## 6. Bash-side equivalents (small parallel ports)

| zsh | bash | Notes |
|---|---|---|
| `history.zsh` setopts | `bashrc.d/010_history.sh`: `HISTFILE`, `HISTSIZE`, `HISTFILESIZE`, `HISTCONTROL=ignoredups:ignorespace`, `shopt -s histappend` | 1:1 concept map, ~8 lines |
| `replay_path_adds` | **not needed** | macOS `path_helper` runs *before* `~/.bash_profile` in bash, so user prepends already win; Linux has no path_helper. The replay exists only because `/etc/zprofile` runs *after* `~/.zshenv` in zsh |
| zmx host-name map | portable `case` function in `rc.sh` | `ZMX_SESSION_PREFIX="$(case $(hostname -s) in miraclemax) echo mmax;; … esac)."` — no assoc array needed |
| completions | come from `hooks.sh` evals (gh, uv, devbox, tailscale, jj, wt, fzf all emit bash completions) | bash-completion package itself optional/out of scope |

---

## 7. Risks & mitigations

| Risk | Mitigation |
|---|---|
| **zsh macOS replay regression** (path_helper ordering) | `paths.zsh` untouched; `.zshenv` keeps sourcing it *before* `env.sh`; verify with a login zsh on macOS |
| **`add_to_path` override trap** — `env.sh` clobbering the zsh recording version | the `command -v add_to_path` guard + fixed source order (paths.zsh first) |
| `[[ -o interactive ]]` landmine silently killing cache refresh in bash | `is_interactive()` shim (verified in sandbox, both shells, no zsh regression) |
| Shared `env.sh` in non-interactive zsh (every zsh reads `.zshenv`) | secrets self-guard via `is_interactive`; brew/nix eval is idempotent (already runs for every zsh today) |
| `export SHELL=$(which zsh)` is zsh-intent | stays in `.zshenv` preamble, NOT in `env.sh` |
| `ZDOTDIR` must be set before zsh looks up rc files | stays in `.zshenv` preamble ahead of all sources |
| `print -P` colored brew warning (zsh-only) | `env.sh` uses a plain `echo` warning — deliberate cosmetic downgrade; alternative: keep the warning in `.zshenv` and let `env.sh` stay silent |
| chezmoi template conditional (darwin `pinentry`) | `rc.sh` needs `.tmpl` suffix or the alias moves to a per-OS file |
| **EDITOR drift** (`nvim` in zsh vs `vim` in bash) | resolved by the shared export — pick one (proposal: `nvim`) |
| `bashrc.d` contains a non-managed file (`001_bob_vim.sh`) | the `for rc in ~/.bashrc.d/*` loop stays, so it keeps loading |
| Same-second mtime granularity on cache invalidation | pre-existing zsh behavior; document, don't fix in this change |
| `bws`/`jq` missing from PATH (rare: `nix develop` on nix-config) → all-empty cache write | the `command -v bws` guard in `secrets.sh` (§3.4); empty cache never written, stale good cache survives |
| `env.sh` prepends user bins in `nix develop` shells (shadowing dev-env bins) | parity with today's `.bashrc`; no clean `nix develop` detection marker exists; narrow, infrequent surface — accepted |
| Headless servers: no GUI keyring | `secret-tool` branch no-ops; designed fallback is `BWS_ACCESS_TOKEN` env var; verify in server checklist (§9) |
| Shared files land on PATH (`~/.config/shell/` is not on PATH — good) | keep `secrets.sh` non-executable like `paths.zsh` |

---

## 8. Migration plan (phased, each phase independently shippable)

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
   decision, `cdzsh`→`cdshell`, `EDITOR` resolution.
6. **Phase 5 — optional polish:** portable zmx function, fzf special-case
   elimination, `rc.sh.tmpl` decision.

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
      loads shared layer; secrets no-op gracefully without a keyring;
      `BWS_ACCESS_TOKEN` env-var path works.
- [ ] Non-interactive `zsh -c` / `bash -c`: env vars + PATH correct; **no**
      network calls from secrets (guards hold).
- [ ] `chezmoi diff` shows only intended moves; `chezmoi apply` idempotent;
      re-sourcing either rc twice is harmless.
- [ ] zsh startup time not regressed (zinit still lazy-loads).
- [ ] `grep -rn "bash" zshrc.d/` and vice-versa: no cross-shell conditionals
      crept in — the only one allowed is the fzf line in `hooks.sh`.

## 10. Open questions

(Answered during review: interactive bash runs on headless NixOS servers and —
narrowly — `nix develop` on nix-config; devenv preserves the parent shell and
adds no bash surface. See §1. The shared layer is justified.)

1. Do you want bash parity for zinit/syntax-highlighting (ble.sh), or is
   "no plugin manager in bash" acceptable? (Proposal: acceptable — bash stays
   lean.)
2. `EDITOR`: `nvim` everywhere (proposal) or `vim` stays in bash?
3. Should `hooks.sh` keep the explicit per-tool lines (§4.2) or become a data
   table? (Proposal: explicit lines — the rows already differ in guards and
   argument shapes; a table would fight reality.)
4. **Future direction (non-blocking):** other projects use secretspec (a
   storage-agnostic secret manager that can proxy BWS). This project stays on
   chezmoi's native BWS integration, so the cache in `secrets.sh` is treated as
   permanent infrastructure, not transitional. Revisit only if secretspec
   gains chezmoi support and this repo migrates.
