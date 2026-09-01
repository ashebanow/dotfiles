# fzf: `eval "$(fzf --zsh)"` vs `source <(fzf --zsh)` — can the branch die?

**Ticket:** https://linear.app/boxbow/issue/BOX-115/fzf-eval-vs-source
**Design context:** `docs/BASH_UPGRADE.md` §4.2 — the single structural shell branch in the
whole design is:

```sh
command -v fzf && { [ "$_SHELL_NAME" = zsh ] && source <(fzf --zsh) || eval "$(fzf --bash)"; }
```

**Question:** can `eval "$(fzf --zsh)"` replace `source <(fzf --zsh)` in interactive zsh
without regression, deleting the branch entirely and leaving zero shell branches?

**Answer (short):** yes. `eval "$(fzf --zsh)"` is behaviorally equivalent to
`source <(fzf --zsh)` in interactive zsh for fzf 0.74.3 / zsh 5.9.2. The branch is
deletable — the design reaches zero shell branches. Details and evidence below.

---

## 1. Versions tested

| Component | Version |
|---|---|
| fzf | `0.74.3 (refs/tags/v0.74.3)` |
| zsh | `5.9.2 (aarch64-apple-darwin25.6.0)` (nix store `/run/current-system/sw/bin/zsh`) |
| bash | `GNU bash 5.3.15(1)-release` (nix store, `--norc` interactive) |

## 2. Test setup

Harness recreated from the precedent PTY driver `/tmp/bws-test/drive.py` (python
`pty.fork()` driving a genuinely interactive shell on a real tty), hardened with
expect-style prompt synchronization, a proper winsize (`40x120`) so fzf can draw,
and guaranteed child cleanup. Lives at `/tmp/fzf-eval-test/`:

- `zdot-src/.zshrc` — **only** `PROMPT='ZSRC> '` + `source <(fzf --zsh)` (scenario A)
- `zdot-eval/.zshrc` — **only** `PROMPT='ZEVL> '` + `eval "$(fzf --zsh)"` (scenario B)
- `zdot-bash/.bashrc` — PS1 + `eval "$(fzf --bash)"` (scenario C, sanity)
- `drive2.py`, `transcript-A-source.txt`, `transcript-B-eval.txt`, `transcript-C-bash.txt`

Isolation: `ZDOTDIR` points at the sandbox dirs, `HOME` is a fresh sandbox home,
`FZF_*` env vars are scrubbed from the environment, `TERM=xterm-256color`. The
user's real config cannot interfere. fzf's own widget machinery (the `$(...)` +
`< /dev/tty` pattern) works under this PTY; fzf 0.74.3 renders its UI on
`/dev/tty` with the synchronized-output protocol (`\x1b[?2026h`) rather than the
alternate screen, so detection used that escape.

## 3. Primary source: the generated `fzf --zsh` script (fzf 0.74.3)

`fzf --zsh` emits 683 lines of static zsh (`key-bindings.zsh` + `completion.zsh`
sections). Static analysis for eval-vs-source hazards — **none found**:

- No shell-level `$0` usage (the only `$0` hits are inside double-quoted `awk`
  programs, e.g. `'{ cmd=$0; ... }'` — awk's field, not the shell's).
- No `zsh_eval_context` / `ZSH_EVAL_CONTEXT` checks (eval would add `eval` to that
  array; source adds `file` — fzf never inspects it).
- No `LINENO`, no top-level `return` / `trap` / `autoload`. Every `return` is
  inside a function body (`fzf-file-widget`, `fzf-cd-widget`, etc.).
- Both sections are self-guarded and option-safe, so re-loading is idempotent:

```zsh
# key-bindings section (line 40):
if [[ -o interactive ]]; then
  ...
fi
} always {
  eval $__fzf_key_bindings_options
  'unset' '__fzf_key_bindings_options'
}

# completion section (line 284): the 'emulate' runs outside the guard (see #3731),
# the try-always restore is identical:
'builtin' 'emulate' 'zsh' && 'builtin' 'setopt' 'no_aliases'
{
if [[ -o interactive ]]; then
  ...
fi
} always {
  # Restore the original options.
  eval $__fzf_completion_options
  'unset' '__fzf_completion_options'
}
```

- Widget registration is plain `zle -N` + `bindkey` (current-shell state, identical
  under source and eval):

```zsh
zle     -N            fzf-file-widget
bindkey -M emacs '^T' fzf-file-widget
bindkey -M vicmd '^T' fzf-file-widget
bindkey -M viins '^T' fzf-file-widget
zle     -N            fzf-history-widget
bindkey -M emacs '^R' fzf-history-widget
...
zle     -N   fzf-completion
bindkey '^I' fzf-completion
```

- The script ends with a comment (`### end: completion.zsh ###`), so
  `$(...)` trailing-newline stripping is harmless.
- Re-init guard: `[ -z "$fzf_default_completion" ] && { ... }` snapshots the `^I`
  binding only on first load, so a second eval/source skips that block.

The bash side (`fzf --bash`, 939 lines) self-guards with `if [[ $- =~ i ]]; then`
and, for bash ≥ 4, registers bindings with `bind -m emacs-standard -x '"\C-t": fzf-file-widget'`
and `bind -m emacs-standard -x '"\C-r": __fzf_history__'`.

## 4. Per-scenario results (interactive zsh under the PTY)

Scenario A: `.zshrc` does `source <(fzf --zsh)`.
Scenario B: `.zshrc` does `eval "$(fzf --zsh)"`.

| Check | A: source | B: eval |
|---|---|---|
| Init stderr / warnings | none | none |
| Prompt renders, commands work after init | yes | yes |
| `bindkey -L \| grep -i fzf` (initial) | 4 lines | 4 lines |
| `zle -l \| grep -i fzf` (initial) | 4 widgets | 4 widgets |
| `whence -w` of the 11 fzf functions | all `function` | all `function` |
| Re-init (same line again) errors | none | none |
| `bindkey`/`zle` after re-init | same 4, no duplicates | same 4, no duplicates |
| E2E: press `^T` → fzf UI opens | yes | yes |
| E2E: Enter inserts `HELLO-MARKER-12345` into the edit line | yes | yes |
| E2E: prompt recovers after widget | yes | yes |

Exact `bindkey -L | grep -i fzf` output — **byte-identical between A and B**:

```zsh
bindkey "^I" fzf-completion
bindkey "^R" fzf-history-widget
bindkey "^T" fzf-file-widget
bindkey "^[c" fzf-cd-widget
```

`zle -l | grep -i fzf` — identical in both:

```zsh
fzf-cd-widget
fzf-completion
fzf-file-widget
fzf-history-widget
```

`whence -w fzf-file-widget fzf-cd-widget fzf-history-widget fzf-completion
_fzf_path_completion _fzf_dir_completion __fzf_defaults __fzf_exec_awk
__fzf_select __fzfcmd __fzf_comprun` — identical in both: every name reported
as `function`.

Notes:
- fzf 0.74.3 binds `^T` (file), `^R` (history), ALT-C `^[c` (cd), TAB `^I`
  (completion). There is **no `^G` binding** in this version (the ticket's `^G`
  example is from older fzf layouts).
- The end-to-end widget proof (^T → fzf → Enter → text lands in the edit line →
  prompt recovers) is the strongest signal: the whole binding→widget→fzf→insert
  chain works identically under eval.

## 5. Re-eval safety

Both variants were run **twice in the same shell** (the init line at startup, then
the identical line again at the prompt):

- No errors, no warnings, no duplicate bindings (`bindkey -L` still lists each
  binding once; `zle -l` still lists each widget once).
- Reason, from the primary source: `bindkey` re-binding replaces rather than
  appends; `zle -N` on an existing widget name re-registers silently; function
  redefinition is a no-op error-wise; the `{ } always { }` option save/restore
  re-runs cleanly; and the `fzf_default_completion` snapshot is guarded by
  `[ -z "$fzf_default_completion" ]` so the `^I` fallback logic doesn't re-run.
- This matches the acceptance criterion in `BASH_UPGRADE.md` §9:
  "re-sourcing either rc twice is harmless."

## 6. Bash sanity check (scenario C) — `eval "$(fzf --bash)"`

The design's bash side is already `eval "$(fzf --bash)"`; confirmed fine as-is:

- Pre-eval: `bind -p -m emacs-standard | grep -ic fzf` = 0, no fzf functions.
- `eval "$(fzf --bash)"` → exit 0, zero stderr.
- Post-eval: `type __fzf_select__ __fzf_cd__ __fzf_history__` → all 3 `is a
  function`; `declare -F | grep -i fzf` lists 20+ functions
  (`__fzf_select__`, `__fzf_cd__`, `__fzf_history__`, `fzf-file-widget`,
  `__fzf_comprun`, `_fzf_complete_*`, …).
- Re-eval in the same shell: exit 0, no errors, no duplicates.
- E2E: press `^T` → fzf UI opens → Enter inserts the selected item → prompt
  recovers.
- Instrumentation note: `bind -p` does **not** dump `-x` (shell-command) bindings,
  so `bind -p | grep fzf` returning 0 after init is expected, not a failure; the
  `bind -x` registration is real (proven by the working `^T`).

## 7. Recommendation

**Delete the branch.** Change the single structural special case in `hooks.sh`
§4.2 to:

```sh
command -v fzf && eval "$(fzf --$_SHELL_NAME)"
```

which matches the pattern of every other tool-init line in `hooks.sh` (keyed by
tool, substituted shell name). This leaves **zero shell branches** in the design,
and the §9 acceptance item "the only one allowed is the fzf line" becomes
moot — `grep -rn "bash" zshrc.d/` should find no cross-shell conditionals.

Caveats (all non-blocking):

- **Equivalence is per-fzf-version.** The generated script is static, and 0.74.3
  contains none of the constructs that would diverge under eval vs source
  (`$0`, `zsh_eval_context`, top-level `return`, `LINENO`, `trap`). If a future
  fzf version started emitting one of those, re-test. Cheap to re-run: the
  harness is at `/tmp/fzf-eval-test/`.
- `eval` buffers the ~683-line script (~30 KB) in memory vs `source` streaming
  from the fd; no observable difference (startup cost is dominated by the fzf
  process spawn either way).
- In non-interactive shells the generated script is inert by design
  (`[[ -o interactive ]]` guard in zsh, `[[ $- =~ i ]]` in bash), so the line is
  safe even if `hooks.sh` ever ran in a non-interactive context.
- The zsh completion widget (`fzf-completion`) consults `compdef` presence at
  invocation time; in the real config compinit has already run (hooks.sh is
  sourced after `zshrc.d`), which is unchanged by source-vs-eval.

## 8. Reproduction

```bash
cd /tmp/fzf-eval-test && python3 drive2.py
```

Transcripts: `transcript-A-source.txt`, `transcript-B-eval.txt`,
`transcript-C-bash.txt`. Primary source captured at
`/tmp/fzf-zsh-generated.sh` (from `fzf --zsh`) and `/tmp/fzf-bash-generated.sh`
(from `fzf --bash`).
