# hooks.sh: audit bash support per tool

**Ticket:** https://linear.app/boxbow/issue/BOX-116/hookssh-audit-bash-support-per-tool
**Date:** 2026-07 (research pass)
**Scope:** Every tool-init line proposed for `~/.config/shell/hooks.sh` in
[`docs/BASH_UPGRADE.md`](../BASH_UPGRADE.md) §4.2. Verifies (a) the zsh shape
already proven in `home/private_dot_config/zsh/zshrc.d/*.zsh`, and (b) the
corresponding bash shape and its exact flag form.

## Method

- Installed tools: ran the proposed invocation for both `bash` and `zsh` words
  on this machine (darwin, nix-managed; `/bin/bash` for bash checks, zsh 5.9.2),
  piped each output through the target shell's syntax checker
  (`bash -n` / `zsh -n`), and eval'd the fzf outputs in-session. Outputs were
  inspected for plausible init content (function defs, `bind`/`bindkey`/
  `compdef` calls, `PROMPT_COMMAND`/`precmd_functions` registration) and for
  stderr noise.
- Absent tools: shapes verified against primary sources (official repo README,
  official docs, or tool source), not secondary write-ups.

## Per-tool table

Installed tools (verified by running the commands on this machine):

| Tool | Version | zsh shape OK? | bash shape OK? | Correction needed |
|---|---|---|---|---|
| direnv | 2.37.1 | ✅ `direnv hook zsh` | ✅ `direnv hook bash` | none |
| starship | 1.26.0 | ✅ `starship init zsh` | ✅ `starship init bash` | none |
| gh | 2.98.0 | ✅ `gh completion -s zsh` | ✅ `gh completion -s bash` | none (`-s` = documented `--shell`) |
| gh copilot alias | 2.98.0 (builtin preview) | ⚠️ shape `gh copilot alias -- zsh` OK, but errors when Copilot CLI absent | ⚠️ same for bash | **guard, not shape** — see notes |
| uv | 0.12.5 | ✅ `uv generate-shell-completion zsh` | ✅ `uv generate-shell-completion bash` | none |
| uvx | 0.12.5 | ✅ `uvx --generate-shell-completion zsh` | ✅ `uvx --generate-shell-completion bash` | none (`--` required; no-dash variant fails) |
| determinate-nixd | 3.22.2 | ✅ `determinate-nixd completion zsh` | ✅ `determinate-nixd completion bash` | none |
| devenv | 2.2.2 | ✅ `devenv hook zsh` | ✅ `devenv hook bash` | none (outputs differ by design) |
| tailscale | 1.102.3 | ✅ `tailscale completion zsh` | ✅ `tailscale completion bash` | none |
| wt | 0.74.0 | ✅ `wt config shell init zsh` | ✅ `wt config shell init bash` | none |
| zmx | 0.7.0 | ✅ `zmx completions zsh` | ✅ `zmx completions bash` | none |
| fzf | 0.74.3 | ✅ `fzf --zsh` (eval works too) | ✅ `fzf --bash` | **special case deletable** — see notes |
| thefuck | absent | ✅ `thefuck --alias` (shell-agnostic) | ✅ same line | none |
| tv (television) | absent | ✅ `tv init zsh` (official README) | ✅ `tv init bash` (official README) | none |
| devbox | absent | ✅ `devbox completion zsh` (official docs) | ✅ `devbox completion bash` (official docs) | none |
| jj | absent | ✅ `COMPLETE=zsh jj` (official docs) | ✅ `COMPLETE=bash jj` (official docs) | none (docs use `source <(…)`; plan's `eval "$(…)"` is equivalent) |

**Every tool on the plan has a working bash shape. No tool is zsh-only.** All
16 proposed lines survive with their exact argument shapes; the only real
issues are two guard/logic-level findings (gh copilot, fzf), below.

## Findings

### 1. gh copilot alias — guard is inverted and errors when Copilot CLI is absent

- The plan line `eval "$(gh copilot alias -- "$_SHELL_NAME")"` has the correct
  shape for both shells (`--` before the shell word is required — verified via
  `gh copilot alias -- bash` / `-- zsh`). The note "keeps its extension-existence
  guard" is the problem:
- The guard inherited from `version-control.zsh` is **logically inverted**:
  `if ! gh extension list | grep -q gh-copilot; then eval "$(gh copilot alias -- zsh)"; fi`
  runs the eval only when the `gh-copilot` extension is **not** installed.
- On this machine the extension **is** installed (`gh-copilot` v1.1.1) and the
  Copilot CLI is **absent**, so the line is currently skipped — but the guard's
  polarity means the moment the extension is absent, the eval runs and fails:
  `gh copilot alias -- <shell>` prints `! Copilot CLI not installed` to **stderr**
  and exits 1 (`gh copilot --version` likewise: rc 1).
- Recommendation: guard on Copilot CLI availability, e.g.
  `if gh copilot --version >/dev/null 2>&1; then eval "$(gh copilot alias -- "$_SHELL_NAME")"; fi`
  (or `command -v copilot`). This also fixes the polarity so the aliases
  actually appear when the CLI is present.

### 2. fzf — the one "structural special case" can be deleted (zero shell branches)

- The plan's `{ [ "$_SHELL_NAME" = zsh ] && source <(fzf --zsh) || eval "$(fzf --bash)"; }`
  is unnecessary. Verified:
  - `eval "$(fzf --zsh)"` runs clean in zsh 5.9.2 (rc 0; the output's `bindkey`
    calls execute fine under eval). No need for `source <(…)`.
  - fzf's flags are literally `--bash` / `--zsh`, so the shell word plugs in:
    `command -v fzf && eval "$(fzf --$_SHELL_NAME)"`.
- This removes the only literal shell branch the whole design allows, per the
  plan's own §4.2 note ("If `eval "$(fzf --zsh)"` proves fine in zsh … the fzf
  special-case can be deleted entirely").

### 3. jj — shape correct; docs show `source <(…)`, plan uses `eval "$(…)` (equivalent)

- Official docs (install-and-setup.md, "Dynamic completions") recommend
  `source <(COMPLETE=bash jj)` / `source <(COMPLETE=zsh jj)`. The plan's
  `eval "$(COMPLETE="$_SHELL_NAME" jj)"` produces the identical text and evals
  it — equivalent. The env-var form `COMPLETE=<shell> jj` (not
  `jj completion <shell>`) is confirmed as the dynamic-completion mechanism.
- Also on record: `source <(jj util completion bash|zsh)` is the **standard**
  (non-dynamic) completion path if the dynamic engine misbehaves.

### 4. Minor audit notes (not plan corrections)

- `determinate-nixd --version` is **not** a valid flag (`error: unexpected
  argument '--version'`); version comes from `determinate-nixd version`
  (3.22.2 here). The plan's completion line is unaffected.
- `uvx --generate-shell-completion` (double dash) is required; the no-dash
  `uvx generate-shell-completion` fails, trying to resolve
  `generate-shell-completion` as a package.
- `devenv hook bash` vs `devenv hook zsh` differ deliberately: bash registers
  via `PROMPT_COMMAND`, zsh via `precmd_functions`. The shell word matters.
- `gh completion -s` is the documented shorthand for `--shell` — gh's own
  `gh completion --help` shows `eval "$(gh completion -s bash)"`.

## Flag-shape corrections list (every §4.2 line needing adjustment)

1. **gh copilot alias** — keep the shape `gh copilot alias -- "$_SHELL_NAME"`,
   but replace the inherited inverted guard with a Copilot-CLI availability
   check:
   `command -v gh && gh copilot --version >/dev/null 2>&1 && eval "$(gh copilot alias -- "$_SHELL_NAME")"`
2. **fzf** — delete the special-case branch; use the shared substitution like
   every other line:
   `command -v fzf && eval "$(fzf --$_SHELL_NAME)"`
3. All other lines: **no change** — exact shapes in §4.2 are correct for both
   bash and zsh as written (including `gh completion -s`, `uvx --generate-shell-completion`,
   `devbox completion`, `determinate-nixd completion`, `devenv hook`,
   `tailscale completion`, `command wt config shell init`, `zmx completions`,
   `COMPLETE="$_SHELL_NAME" jj`, `thefuck --alias`, `direnv hook`, `starship init`,
   `tv init`, `uv generate-shell-completion`).

## Sources

Primary-source citations per claim:

- **Local command output (this machine)** — versions: `direnv 2.37.1`,
  `starship 1.26.0`, `gh 2.98.0`, `uv/uvx 0.12.5`, `determinate-nixd 3.22.2`
  (via `determinate-nixd version`), `devenv 2.2.2`, `tailscale 1.102.3`,
  `wt 0.74.0`, `zmx 0.7.0`, `fzf 0.74.3`. Syntax validation: every generated
  bash output passed `bash -n`; every zsh output passed `zsh -n` (zsh 5.9.2).
  In-session eval probes for `fzf --zsh` (zsh) and `fzf --bash` (bash): rc 0.
  Negative control: `uvx generate-shell-completion zsh` (no dashes) fails.
- **gh** — `gh completion --help` (shows `eval "$(gh completion -s bash)"`),
  `gh copilot --help` / `gh copilot alias -- <shell>` local output
  (`! Copilot CLI not installed`, exit 1, stderr).
- **television (tv)** — https://github.com/alexpasmantier/television README
  "Shell Integration": `eval "$(tv init zsh)"` / `eval "$(tv init bash)"`.
- **devbox** — https://www.jetify.com/devbox/docs/quickstart/ and CLI reference
  https://www.jetify.com/devbox/docs/devbox/cli-reference/devbox-completion/
  (subcommands `devbox completion bash|fish|zsh`, "Generate the autocompletion
  script for the specified shell"); cobra-standard shape confirmed in repo
  (no custom completion command in `internal/boxcli`).
- **jj** — https://github.com/jj-vcs/jj/blob/main/docs/install-and-setup.md
  §"Command-line completion": `source <(COMPLETE=bash jj)`,
  `source <(COMPLETE=zsh jj)` (dynamic), `source <(jj util completion bash|zsh)`
  (standard).
- **thefuck** — https://github.com/nvbn/thefuck README ("eval $(thefuck --alias)",
  Bash/Zsh/Fish/Powershell/tcsh); source `thefuck/entrypoints/alias.py`
  (`shell.app_alias(known_args.alias)` with the auto-detected shell) and
  `thefuck/shells/__init__.py` (shell detection from process/env, `TF_SHELL`
  override; bash + zsh both first-class).
- **devenv** — `devenv hook --help` (local): "bash: eval \"$(devenv hook bash)\"" /
  "zsh: eval \"$(devenv hook zsh)\"".
- **uv/uvx** — `uv generate-shell-completion --help` (local): `<SHELL>` possible
  values include `bash` and `zsh`; `uv completion` does not exist.
- **tailscale / wt / zmx / determinate-nixd** — local `--help` output:
  `tailscale completion <shell>` (cobra), `wt config shell init <bash|fish|nu|zsh|powershell>`,
  `zmx completions <bash|zsh|fish|nu>`, `determinate-nixd completion <bash|elvish|fish|powershell|zsh>`.
