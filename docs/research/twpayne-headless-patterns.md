# twpayne/dotfiles: how the `headless` flag is actually used

**Ticket:** https://linear.app/boxbow/issue/BOX-125/research-twpayne-dotfiles-headless-patterns
**Date:** 2026-09 (research pass)
**Scope:** github.com/twpayne/dotfiles analyzed at commit
`360055acc70b1ab78a5782bf90b8aa2f8ce65ff2` (2026-07-18), the commit that our
`home/.chezmoi.toml.tmpl` header comments point at. Primary sources only: the
repo itself (full clone + git history), chezmoi's official docs, and chezmoi's
Go source. Everything below is cited; ambiguous or version-sensitive claims are
flagged inline.

**Question:** our `.chezmoi.toml.tmpl` computes `headless` (copied from
twpayne's) but never consumes it. How does twpayne consume it, and what should
our `.chezmoiignore` gating look like?

---

## TL;DR (the two findings that change the plan)

1. **twpayne does not gate `.chezmoiignore` on `headless`.** His
   `.chezmoiignore.tmpl` has *never* used `headless` in its entire git history
   (verified by walking every commit that touched the file). It gates on
   `.chezmoi.os` and `.personal` only. `headless` is consumed in exactly two
   places: **`run_*` script templates** (top-of-file `{{ if ... -}}` guards that
   render the script to empty) and **`.chezmoiexternal.toml.tmpl`** (conditional
   archive/file blocks). If we want `.chezmoiignore` gating, that is *our* design
   extension, not a twpayne idiom — but see §5, his `.chezmoiignore` structure is
   directly reusable.
2. **`include_`/`exclude_` source attributes do not exist in chezmoi.** The
   ticket assumed they might. Verified against the official source-state
   attributes reference: the attribute table contains `exact_`, `exclude` is
   only a key inside `.chezmoiexternal` archive entries (which twpayne *does*
   use, for pruning oh-my-zsh archives) and a `diff`/`status`/`verify` config
   key. OS gating in chezmoi is done via `.chezmoiignore` templates, empty
   script templates, or external-file templates — not filename attributes.

---

## 1. The `headless` flag: definition and detection (`.chezmoi.toml.tmpl`)

`headless` is one of four orthogonal boolean feature tags computed in
`home/.chezmoi.toml.tmpl` and stored in `[data]` for all templates:

```
{{ $ephemeral := false }}  # cloud/VM instance
{{ $work := false }}       # work machine
{{ $headless := false }}   # "true if this machine does not have a screen and keyboard"
{{ $personal := false }}   # "true if this machine should have personal secrets"
```

Source: https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoi.toml.tmpl

Detection order (all in the same file):

| Condition | Result |
|---|---|
| `CODESPACES` env, `REMOTE_CONTAINERS_IPC` env, or username ∈ {`root`, `ubuntu`, `vagrant`, `vscode`} | `ephemeral = true`, `headless = true` |
| `.chezmoi.os == "windows"` | `ephemeral = true` (headless untouched) |
| hostname ∈ {`ubuntu`, `ubuntu-26`} | `headless = true`, `personal = true` |
| hostname `zrh-mpl3s` | `work = true` |
| hostname `macbook-air-m3` / `thinkpad` | `personal = true` |
| else if `stdinIsATTY` | prompt once: `promptBoolOnce . "headless" "headless"` and `promptBoolOnce . "ephemeral" "ephemeral"` |
| else (no TTY, unknown host) | `ephemeral = true`, `headless = true` (conservative default) |

Note the **non-TTY default is headless + ephemeral**: any unattended `chezmoi
init --apply` on an unknown machine gets the minimal, non-GUI profile unless it
can prove otherwise. The macOS hostname is read via
`output "scutil" "--get" "LocalHostName"` (his comment: "work around unreliable
hostname on darwin").

Version sensitivity: `stdinIsATTY` and `promptBoolOnce` are template functions
from recent chezmoi; his repo pins a minimum via `.chezmoiversion` = `2.48.1`
(https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/.chezmoiversion).

## 2. `.chezmoiignore.tmpl` — what it actually gates on

His ignore file is a template (`home/.chezmoiignore.tmpl`, extension optional —
the docs say `.chezmoiignore` is templated "whether or not it has a `.tmpl`
extension", https://www.chezmoi.io/reference/special-files/chezmoiignore/). It
has three conditional blocks:

1. `{{ if ne .chezmoi.os "darwin" }}` — ignore macOS-only trees:
   `.chezmoiscripts/darwin/**`, `.config/aerospace`, `.config/homebrew`,
   `.hammerspoon`.
2. `{{ if ne .chezmoi.os "linux" }}` — ignore Linux-only trees:
   `.chezmoiscripts/linux/**`, `.hushlogin`, `.local/bin/nvim`,
   `.local/share/fonts`.
3. `{{ if ne .chezmoi.os "windows" }}` / `{{ else }}` — ignore
   `.chezmoiscripts/windows/**` and `Documents` on non-Windows; on Windows
   ignore a large fixed list (`.zshrc`, `.p10k.zsh`, `.oh-my-zsh`,
   `.ssh/id_rsa*`, `.tmux.conf`, …).
4. `{{ if not .personal }}` — ignore `.config/ghostty`, `.config/psql`,
   `.hammerspoon`, `.pypirc`, `.psqlrc`, `.ssh`, `.gnupg` on non-personal
   machines.

Plus **always-on** entries (not conditional): `.oh-my-zsh/cache/**`,
`.oh-my-zsh/plugins/**` (with `!` allowlist of the configured plugins — see §5),
`.oh-my-zsh/templates/**`, p10k `.zwc` cache files.

Sources: https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiignore.tmpl ;
official `ne`-inversion idiom documented at
https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/ ("only
install `.work` if hostname is `work-laptop`" → write "ignore unless").

**Why scripts appear in `.chezmoiignore`:** chezmoi does *not* auto-restrict
`.chezmoiscripts/<os>/` subdirectories to that OS — `readScriptsDir` walks the
whole tree with no OS check (Go source:
https://github.com/twpayne/chezmoi/blob/master/internal/chezmoi/sourcestate.go,
`readScriptsDir`, and the `if s.Ignore(targetRelPath)` line inside it, which is
what makes `.chezmoiignore` patterns apply to scripts). Commit `c550edd`
(2022-10-30) "Use .chezmoiignore to exclude scripts by OS" moved that gating
into `.chezmoiignore`:
https://github.com/twpayne/dotfiles/commit/c550edd. Our repo already uses the
same pattern (`.chezmoiscripts/darwin/**` / `.chezmoiscripts/linux/**` in
`home/.chezmoiignore.tmpl`).

## 3. Where `headless` is actually consumed — four scripts + one external block

Every consumer gates with a template conditional that, when false, renders the
whole file to (near-)empty. Chezmoi documents that "if the template resolves to
only whitespace or an empty string, the script will not be executed, which is
useful for disabling scripts dynamically"
(https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/).

| Consumer | Guard | What it controls |
|---|---|---|
| `.chezmoiscripts/run_onchange_after_configure-vscode.sh.tmpl` | `{{ if and (eq .chezmoi.os "darwin" "linux") (not .headless) -}}` | Installs 18 VS Code extensions via `code --force --install-extension …` |
| `.chezmoiscripts/linux/run_onchange_before_install-ghostty.sh.tmpl` | `{{ if and (eq .osid "linux-ubuntu") (not .headless) -}}` | Downloads+installs the Ghostty terminal `.deb` |
| `.chezmoiscripts/linux/run_onchange_before_install-packages.sh.tmpl` | `{{ if not .headless -}}` (inside the debian/raspbian/ubuntu block) | Appends `xclip` to `$packages` and `code` (VS Code) to `$classicSnaps` |
| `.chezmoiscripts/linux/run_onchange_after_configure-gnome.sh.tmpl` | `{{ if (and (not .ephemeral) (not .headless)) -}}` | `gsettings` desktop config: touchpad, favorite-apps dock, ding extensions, mutter keybindings |
| `.chezmoiexternal.toml.tmpl` | `{{- if and (not .ephemeral) (not .headless) }}` … `{{ end }}` | Downloads the four MesloLGS Nerd Font `.ttf`s (p10k font) into `Library/Fonts` (macOS) or `.local/share/fonts` (Linux) |

Sources:
https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiscripts/run_onchange_after_configure-vscode.sh.tmpl ,
…/linux/run_onchange_before_install-ghostty.sh.tmpl ,
…/linux/run_onchange_before_install-packages.sh.tmpl ,
…/linux/run_onchange_after_configure-gnome.sh.tmpl ,
…/home/.chezmoiexternal.toml.tmpl .

Adjacent flags, same mechanism: `run_onchange_after_chsh.sh.tmpl` guards on
`(not .ephemeral)` (only set zsh as the login shell on persistent machines);
`run_onchange_after_set-origin-url.sh.tmpl` guards on `.personal`; the darwin
packages script (`run_onchange_before_install-packages.sh.tmpl`) appends a
large cask/brew block `{{ if .personal }}` (firefox, ghostty, steam, tailscale-app,
vlc, …). Sources: the same scripts directory.

Notably **no `headless` logic exists in his `install.sh`** — it is the generic
`chezmoi init --apply --source=$script_dir` bootstrap, and the README just says
`chezmoi init twpayne`. All machine-class decisions live in the templates, not
in the bootstrap.
https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/install.sh ,
https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/README.md

## 4. What headless machines get vs desktop machines

His headless machines are Ubuntu servers (`ubuntu`, `ubuntu-26`). Because the
toml sets `headless = true` **and** `personal = true` for them, "headless" here
means *no screen/keyboard*, not *no secrets*:

**Headless Ubuntu gets (same as desktop):** the full zsh stack —
`dot_zshrc.tmpl`, `dot_zprofile.tmpl`, `dot_p10k.zsh.tmpl`, oh-my-zsh (with the
plugin allowlist from `[data] zshPlugins`), nvim config, git config incl.
personal tokens (`{{ if .personal }}` blocks: `GITHUB_ACCESS_TOKEN`,
`CHEZMOI_GITHUB_ACCESS_TOKEN` from 1Password), `.ssh`, `.gnupg`, ghostty
*config*, psql config, `.pypirc`. There is **no "minimal shell" for headless** —
his headless servers are just as shell-rich as his laptops.
Sources: https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/dot_zshrc.tmpl ,
…/home/.chezmoiignore.tmpl .

**Headless does NOT get (GUI/desktop-only):**
- VS Code: neither the `code` snap (§3 table) nor the extension-install script.
- Ghostty: the binary/`.deb` (config file still lands).
- `xclip` (X11 clipboard).
- Nerd Fonts for p10k (external block).
- GNOME desktop settings (configure-gnome, additionally guarded by `not .ephemeral`).
- QGIS on ubuntu (`{{ if and (eq .osid "linux-ubuntu") (not .headless) }}` since
  commit `def1627`, 2024-07-31, "Don't install QGIS on headless machines").

In short: **headless = full shell + no GUI binaries / no GUI config apps**, and
the shell itself is untouched. Secrets are gated by `personal`, not `headless`.

## 5. Reusable idioms for our `.chezmoiignore` design

1. **Gate whole trees in `.chezmoiignore.tmpl` with inverted conditionals**
   (`{{ if not .headless }} .config/waybar … {{ end }}`, or the `ne` form from
   the docs). Patterns match *target* paths (`doublestar.Match`), not source
   paths — so `.config/waybar` not `dot_config/waybar`
   (https://www.chezmoi.io/reference/special-files/chezmoiignore/).
2. **`!`-excludes for keep-a-subset**: he ignores `.oh-my-zsh/plugins/**` but
   allowlists the three configured plugins via `{{ range .zshPlugins }}!.oh-my-zsh/plugins/{{ . }}` —
   the `[data] zshPlugins` list in `.chezmoi.toml.tmpl` drives **both** the
   zshrc `plugins=(…)` array and the ignore allowlist. One source of truth,
   data-driven chunking (small file chunks: config stays whole, only what's
   chunked is the plugin list). This is the closest thing in the repo to
   "smaller chunks, no forked layer".
3. **Scripts self-gate with empty-template guards** — wrap the whole script in
   `{{ if and (…) (not .headless) -}}…{{ end -}}`; chezmoi skips scripts whose
   rendered content is empty. This is the only place twpayne consumes `headless`.
   Combine flags when needed: `(not .ephemeral) (not .headless)`.
4. **`headless`-gated downloads belong in `.chezmoiexternal.toml.tmpl`**
   conditional blocks (fonts) — externals are evaluated as templates and can be
   skipped wholesale.
5. **OS-specific script trees still need explicit gating** — `.chezmoiscripts/<os>/**`
   in `.chezmoiignore` (no automatic OS filter in chezmoi); our repo already does this.
6. **Debugging**: `chezmoi ignored` lists what `.chezmoiignore` filters
   (https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/).

## 6. Evolution in twpayne's repo (why it looks this way)

- `69b5361` "Make focal headless" (2021-06-04) and `5dc46b6` "Don't install code
  or vim-gtk on headless machines" (2021-06-04): `headless` introduced in the
  toml and first consumed as an inline `{{ if (not .headless) }}` in the package
  installer. https://github.com/twpayne/dotfiles/commit/69b5361 ,
  https://github.com/twpayne/dotfiles/commit/5dc46b6
- `c550edd` "Use .chezmoiignore to exclude scripts by OS" (2022-10-30): OS gating
  moved from inline conditionals into `.chezmoiignore`.
  https://github.com/twpayne/dotfiles/commit/c550edd
- `d43dc15` "Add .tmpl extension to chezmoi template files": files renamed to
  `.tmpl` (his `.chezmoiignore.tmpl`; the docs note the extension is optional).
- `def1627` (2024-07-31) QGIS, `448f34d` "Don't install Ghostty on headless
  machines" (2025-03-20, one-line change adding `(not .headless)` to the
  ghostty guard): headless gating is *added incrementally* as GUI things are
  discovered, always as script/external guards — never as ignore-file entries.
  https://github.com/twpayne/dotfiles/commit/448f34d

**Takeaway for the plan:** twpayne's evolution shows headless gating accretes at
the *action* layer (installs, config writes) while `.chezmoiignore` stays for
*file-tree* gating keyed on OS/personal. Our plan (`.chezmoiignore` gating on
`headless`) is a legitimate extension — the file-tree mechanism is the right
place for it — but we should expect to also keep twpayne's empty-script guards
for anything that *does something* (package installs, gsettings, VS Code) rather
than just *write a file*.

## 7. Corrections to the ticket's assumptions (things to decide)

1. **`include_`/`exclude_` attributes don't exist** — see TL;DR. Don't design
   around them; use `.chezmoiignore` conditionals. The `exclude` key twpayne
   uses is only for external archives (pruning oh-my-zsh/plugin archives:
   `exclude = ["*/.*", "*/templates", "*/themes"]` in
   `.chezmoiexternal.toml.tmpl`).
2. **twpayne's `headless` ⊥ `personal` (orthogonal).** His headless ubuntu
   servers are also `personal` and get SSH/gnupg/tokens. Our CONTEXT.md instead
   defines headless as "no screen/keyboard, **no personal secrets**, minimal
   toolset" with no `personal` flag
   (https://github.com/ashebanow/dotfiles/blob/main/CONTEXT.md — local copy at
   `CONTEXT.md`). If we gate `.chezmoiignore` on `headless`, our `headless` must
   cover what twpayne gates on `not .personal` *and* `not .headless` (secrets:
   `.ssh`, `.gnupg`, tokens; GUI: waybar/hypr/rofi/etc.). Decide explicitly
   whether headless in our model keeps shell config (twpayne: yes) or minimizes
   it (our CONTEXT.md wording suggests minimal toolset — a divergence to resolve).
3. **Scripts are not skipped automatically by OS subdir** — keep the
   `.chezmoiscripts/<os>/**` ignore entries (already present in our repo).
4. **Version pin:** twpayne's repo requires chezmoi ≥ 2.48.1
   (`.chezmoiversion`); `promptBoolOnce`/`stdinIsATTY` need a recent chezmoi.
   Our repo should confirm its chezmoi version supports whatever we use.

---

## Sources

Primary sources (all claims above trace to these):

- **twpayne/dotfiles @ 360055acc (2026-07-18)** — full clone + `git log`:
  - `home/.chezmoi.toml.tmpl` — https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoi.toml.tmpl
  - `home/.chezmoiignore.tmpl` — https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiignore.tmpl
  - `home/.chezmoiexternal.toml.tmpl` — https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiexternal.toml.tmpl
  - `home/.chezmoiscripts/run_onchange_after_configure-vscode.sh.tmpl` — https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiscripts/run_onchange_after_configure-vscode.sh.tmpl
  - `home/.chezmoiscripts/linux/run_onchange_before_install-ghostty.sh.tmpl` — https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiscripts/linux/run_onchange_before_install-ghostty.sh.tmpl
  - `home/.chezmoiscripts/linux/run_onchange_before_install-packages.sh.tmpl` — https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiscripts/linux/run_onchange_before_install-packages.sh.tmpl
  - `home/.chezmoiscripts/linux/run_onchange_after_configure-gnome.sh.tmpl` — https://github.com/twpayne/dotfiles/blob/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2/home/.chezmoiscripts/linux/run_onchange_after_configure-gnome.sh.tmpl
  - `home/dot_zshrc.tmpl`, `install.sh`, `README.md`, `.chezmoiversion` — same repo/commit tree
  - History: commits `69b5361`, `5dc46b6`, `c550edd`, `d43dc15`, `def1627`, `448f34d`
    (https://github.com/twpayne/dotfiles/commits/360055acc70b1ab78a5782bf90b8aa2f8ce65ff2)
- **Chezmoi official docs:**
  - `.chezmoiignore{,.tmpl}` (template regardless of extension; patterns match target paths; `!` excludes; `doublestar.Match`) — https://www.chezmoi.io/reference/special-files/chezmoiignore/
  - "Manage machine-to-machine differences" (`.chezmoiignore` + `ne` inversion + `chezmoi ignored`) — https://www.chezmoi.io/user-guide/manage-machine-to-machine-differences/
  - "Use scripts to perform actions" (empty-template scripts not executed; `run_`/`run_onchange_`/`run_once_` semantics) — https://www.chezmoi.io/user-guide/use-scripts-to-perform-actions/
  - "Source state attributes" (attribute table — **no `include_`/`exclude_`**) — https://www.chezmoi.io/reference/source-state-attributes/
  - `stdinIsATTY` — https://www.chezmoi.io/reference/templates/functions/stdinIsATTY/
- **Chezmoi Go source:** `internal/chezmoi/sourcestate.go` `readScriptsDir`
  (no OS filter on `.chezmoiscripts/<os>/`; `s.Ignore(targetRelPath)` applies
  `.chezmoiignore` to scripts) — https://github.com/twpayne/chezmoi/blob/master/internal/chezmoi/sourcestate.go
- **Local repo (ashebanow/dotfiles, main):** `home/.chezmoi.toml.tmpl`
  (copied from twpayne @ `436e4e9366667d84493d3504123bb16c89583605`, per its
  header comment), `home/.chezmoiignore.tmpl` (OS gating only, exists today),
  `CONTEXT.md` (headless ⊇ remote, "no personal secrets").
