# chezmoi + `bitwardenSecrets` with no Bitwarden session — failure mode and headless-safe options

**Ticket:** https://linear.app/boxbow/issue/BOX-120/research-chezmoi-bws-bitwardensecrets-behavior-without-a-session
**Date:** 2026-09-01 (research pass, chezmoi v2.72.0 from nixpkgs)
**Scope:** What `chezmoi apply` does when a template calls `bitwardenSecrets`
(and the `bws` integration generally) on a machine with **no** Bitwarden
session, and which mechanisms keep `apply` non-interactive and secret-free on
headless hosts. Trigger: `home/private_dot_hermes/private_config.yaml.tmpl` line
79 calls `(bitwardenSecrets "52eba787-8cb2-41b7-87b1-b4770134b198").value`
(→ `~/.hermes/config.yaml`), which would break a token-less headless apply.

## TL;DR

- **Failure mode (empirically verified):** hard failure, **exit code 1**, no
  interactive prompt, nothing applied. `bws secret get <id>` prints
  `Missing access token` (bws exit 1); chezmoi wraps it as a template
  evaluation error and aborts the whole apply.
- **`.chezmoiignore` exclusion prevents template evaluation entirely.** An
  ignored template is never parsed or executed — verified for both `apply` and
  `diff` (exit 0, no `bws` invocation). Gotcha: ignore patterns match the
  **target** path (`.hermes`), not the source path (`private_dot_hermes`).
- **Recommended headless-safe approach:** ignore `.hermes` in
  `home/.chezmoiignore.tmpl` behind the existing `headless`/`personal` feature
  flags (`{{ if not .personal }}` / `{{ if .headless }}`). Verified working.
- **Backup approaches:** `chezmoi apply --skip-secrets` (skips every template
  containing secret-function calls, exit 0); `BWS_ACCESS_TOKEN` env var
  (non-interactive but keeps secrets — fine for CI/dev, not secret-free);
  `--override-data` **does not help** (see below); `--exclude=templates` works
  but is a broad hammer (skips all `.tmpl` sources).

## 1. How the integration works here (primary sources)

- The template under investigation installs to `~/.hermes/config.yaml`
  (verified: `chezmoi target-path home/private_dot_hermes/private_config.yaml.tmpl`
  → `/Users/ashebanow/.hermes/config.yaml`). Line 79:
  `x-api-key: {{ (bitwardenSecrets "52eba787-8cb2-41b7-87b1-b4770134b198").value }}`
  (source: repo file `home/private_dot_hermes/private_config.yaml.tmpl`).
- `bitwardenSecrets` runs the Bitwarden Secrets CLI (`bws`): "*secret-id* is
  passed to `bws secret get` and the output from `bws secret get` is parsed as
  JSON and returned" — chezmoi docs, `bitwardenSecrets` reference.
- The command and token source: `bitwardenSecrets.command` defaults to `bws`
  (chezmoi config schema, `variables.md.yaml`); the client is invoked as
  `bws secret get <secretID>` with **no** `--access-token` flag unless a second
  argument is passed to the function (chezmoi source,
  `internal/cmd/bitwardensecretstemplatefuncs.go`). With no explicit token
  argument, `bws` obtains the token itself from the environment: "Either set
  the `BWS_ACCESS_TOKEN` environment variable or store the access token in a
  template variable" (chezmoi docs, Bitwarden user guide).
- `BW_SESSION` (classic Bitwarden CLI session) is **not** involved: that
  belongs to the `bitwarden`/`bitwardenFields` functions and the `bw` CLI.
  This repo's `docs/BITWARDEN.md` session machinery (`bw-session-manager`,
  `BW_SESSION`, `bw-open`) feeds the classic CLI only and does nothing for
  `bitwardenSecrets`. The only relevant input for the hermes template is
  `BWS_ACCESS_TOKEN` (or a token passed as the function's second argument).
- `bitwardenSecrets` output is cached per (secret-id, access-token) so repeated
  calls run `bws secret get` once (chezmoi source, `bitwardensecretstemplatefuncs.go`).

## 2. Failure mode with no session — empirically verified

Sandbox: `/tmp/chezmoi-bws-test` with an isolated source dir, destination dir,
and persistent state (so the real `~/.config/chezmoi/chezmoistate.boltdb` and
`~/.hermes` were never touched; real state mtime verified unchanged). Test
template mirrors the hermes line:
`x-api-key: {{ (bitwardenSecrets "52eba787-8cb2-41b7-87b1-b4770134b198").value }}`.
Run with `BWS_ACCESS_TOKEN` and `BW_SESSION` unset, stdin `/dev/null`.

Observed (chezmoi v2.72.0):

```
Error:
   0: Missing access token
Location:
   crates/bws/src/main.rs:65
...
chezmoi: .hermes/config.yaml: template: private_dot_hermes/private_config.yaml.tmpl:6:21:
executing "private_dot_hermes/private_config.yaml.tmpl" at <bitwardenSecrets "52eba787-8cb2-41b7-87b1-b4770134b198">:
error calling bitwardenSecrets: /etc/profiles/per-user/ashebanow/bin/bws secret get 52eba787-8cb2-41b7-87b1-b4770134b198: exit status 1
```

- **Exit code 1.** No interactive prompt is offered; it simply fails. The
  destination is left empty (nothing from the failed apply is written).
- `bws secret get` fails itself with `Missing access token` (observed from the
  installed `bws` binary; it reports the failure at `crates/bws/src/main.rs:65`,
  the bws CLI source location). chezmoi wraps any nonzero `bws` exit as
  `error calling bitwardenSecrets: <command>: exit status N` and the template
  execution fails, aborting the apply.
- `chezmoi diff` fails identically (exit 1) when the template is not ignored.
- Positive control: with `BWS_ACCESS_TOKEN` set, `apply` succeeds (exit 0) and
  the secret value lands in `dest/.hermes/config.yaml`.
- General non-interactive hazard (secondary, distinct from secrets): chezmoi
  also fails when it needs a TTY for its own prompts — e.g. a destination entry
  "has changed since chezmoi last wrote it" → `could not open a new TTY: open
  /dev/tty: device not configured`, exit 1 (observed in the sandbox; prompt
  logic is chezmoi source `internal/cmd/config.go`, `defaultPreApplyFunc`).
  `--force` suppresses these prompts.

## 3. Does `.chezmoiignore` prevent template evaluation? Yes.

- An ignored file is removed from the source state before any template
  evaluation; ignored templates are **never executed** — no `bws` invocation,
  no error. Verified: with `.chezmoiignore` containing `.hermes`, a token-less
  `chezmoi apply` exits **0**, applies everything else, and omits
  `.hermes/config.yaml`; `chezmoi diff` likewise exits 0 with no `.hermes`
  diff. Ignored entries also don't appear in `chezmoi managed`.
- **Gotcha 1 — patterns match target paths, not source paths.** ".chezmoiignore
  patterns ... match against the target path, not the source path" (chezmoi
  docs, `.chezmoiignore` reference). The pattern must be `.hermes` (the target
  name of `private_dot_hermes`), not `private_dot_hermes`. Verified
  empirically both ways: the source-name pattern does **not** ignore the file
  (apply still fails on `bws`), the target-name pattern does.
- **Gotcha 2 — `.chezmoiignore` is itself a template** (whether or not it has a
  `.tmpl` extension; chezmoi docs). This repo's file is already
  `home/.chezmoiignore.tmpl` with per-OS conditionals — the same mechanism
  works for the new entry (verified below).
- **Gotcha 3 — `.chezmoiignore` files in source subdirectories apply only to
  that subdirectory** (chezmoi docs). The root-level ignore is the right place.

## 4. Headless-safe options, evaluated

Verified against the same sandbox (all with `BWS_ACCESS_TOKEN` unset):

| Option | Result | Verdict |
|---|---|---|
| `.chezmoiignore` with `.hermes` | exit 0, template never evaluated | **Recommended (declarative)** |
| `chezmoi apply --skip-secrets` | exit 0; secret templates skipped, non-secret files applied | Good per-invocation fallback; skips *all* secret templates; still creates the empty parent dir (`.hermes/`) because the directory entry itself isn't a secret template |
| `BWS_ACCESS_TOKEN` env var | exit 0, secrets injected | Non-interactive but **not secret-free**; right for CI/dev machines that export a token (this repo already treats it that way — see `docs/BASH_UPGRADE.md` §1: headless nix-config shells are "deliberately token-less", env fallback is for CI/dev) |
| `--override-data` / `--override-data-file` (`--data`) | **does not help** | It only sets template *data* variables; `bitwardenSecrets` is a template *function* and is still invoked → same exit 1. Only helps if the template is rewritten to read a data var instead of calling `bitwardenSecrets` |
| `--exclude=templates` | exit 0, but **all** `.tmpl` sources skipped (nothing applied in the sandbox) | Broad hammer; also skips non-secret templates (e.g. `dot_plain.tmpl`, and in this repo `dot_justfile.tmpl`, `dot_zshenv.tmpl`) |
| `--exclude` with other entry types (`dirs`, `files`, `scripts`, `encrypted`, …) | n/a | Entry-type filter only; cannot exclude a specific file (chezmoi source, `entrytypeset.go`) |

### Mechanism of `--skip-secrets` (primary source)

`bitwardenSecrets` begins with `chezmoi.SkipTemplateIf(c.skipSecrets)`
(chezmoi source, `internal/cmd/bitwardensecretstemplatefuncs.go`);
`SkipTemplateIf` panics with `errSkipTemplate` when skipping
(`internal/chezmoi/templatefuncs.go`), and the source state treats that as
"skip this entry, no error" (`internal/chezmoi/sourcestate.go`,
`case errors.Is(err, errSkipTemplate): return nil`). Flag exists as a
persistent flag on all commands (`--skip-secrets`, "Skip all templates
containing secrets"; `chezmoi apply --help`).

## 5. Recommended change for this repo

Add a feature-flag-gated ignore for `.hermes` in `home/.chezmoiignore.tmpl`
(matching the existing per-OS conditional style):

```
{{ if not .personal }}
.hermes
{{ end }}
```

or equivalently `{{ if .headless }}`. Rationale:

- `home/.chezmoi.toml.tmpl` already computes `headless` and `personal` per
  host; every headless host in the list (lumquat, calamansi, kumquat, rangpur,
  tangelo, unknown hosts) is non-personal and has no token in user shells
  (`docs/BASH_UPGRADE.md` §1). `.hermes/config.yaml` contains a personal
  secret (the exa MCP `x-api-key`), so `not .personal` is the semantically
  correct gate.
- Verified in the sandbox: a `.chezmoiignore` template with
  `{{ if not .personal }}.hermes{{ end }}` + `--override-data '{"personal": false}'`
  → exit 0, no template evaluation; with `personal: true` → the ignore does not
  apply and the token-less apply fails with the `bws` error (exit 1). The
  conditional works in both directions.
- The target-path gotcha matters here too: pattern is `.hermes`, not
  `private_dot_hermes`.

If the hermes config must still be deployed on headless hosts (empty key), the
alternative is to rewrite the template to read a data var
(`x-api-key: {{ .hermesExaApiKey | default "" }}`) and supply the key via
`--override-data-file` on personal machines — more invasive, and not needed if
hermes doesn't run on those hosts.

## 6. Sources

Primary sources per claim:

- **Failure mode / exit codes** — empirical: sandbox at `/tmp/chezmoi-bws-test`
  (source+dest+state isolated), chezmoi v2.72.0 (nixpkgs), `bws` at
  `/etc/profiles/per-user/ashebanow/bin/bws`. Output quoted in §2. Positive
  control with `BWS_ACCESS_TOKEN` set: exit 0.
- **`bitwardenSecrets` semantics** — chezmoi docs
  https://www.chezmoi.io/reference/templates/bitwarden-functions/bitwardenSecrets/
  (source markdown `assets/chezmoi.io/docs/reference/templates/bitwarden-functions/bitwardenSecrets.md`,
  twpayne/chezmoi @ master): "passed to `bws secret get`", output parsed as
  JSON, optional access-token argument passed with `--access-token`, output
  cached.
- **`bws`/`BWS_ACCESS_TOKEN` contract** — chezmoi docs
  https://www.chezmoi.io/user-guide/password-managers/bitwarden/ (source
  markdown `assets/chezmoi.io/docs/user-guide/password-managers/bitwarden.md`):
  "Either set the `BWS_ACCESS_TOKEN` environment variable or store the access
  token in a template variable". `bitwardenSecrets.command` default `bws` —
  chezmoi config schema `assets/chezmoi.io/docs/reference/configuration-file/variables.md.yaml`.
- **chezmoi source (twpayne/chezmoi @ master)** —
  `internal/cmd/bitwardensecretstemplatefuncs.go` (`bws secret get <id>`,
  `chezmoi.SkipTemplateIf(c.skipSecrets)`, output cache);
  `internal/chezmoi/templatefuncs.go` (`SkipTemplateIf` panics
  `errSkipTemplate`); `internal/chezmoi/sourcestate.go` (`errSkipTemplate` →
  entry skipped, no error); `internal/cmd/config.go` (`defaultPreApplyFunc`
  prompt logic; `--skip-secrets` and `--override-data` flag registration, the
  latter parsed with `json.Unmarshal` — i.e. a JSON object, not `key=value`);
  `internal/chezmoi/entrytypeset.go` (entry-type list for `--exclude`).
- **`.chezmoiignore` semantics** — chezmoi docs
  https://www.chezmoi.io/reference/special-files/chezmoiignore/ (source
  markdown `assets/chezmoi.io/docs/reference/special-files/chezmoiignore.md`):
  patterns match the **target path** via `doublestar.Match`; interpreted as a
  template whether or not it has a `.tmpl` extension; subdirectory ignore files
  apply only to that subdirectory. Target-path matching additionally verified
  empirically (source-name pattern fails to ignore, target-name pattern works).
- **Repo context** — `home/private_dot_hermes/private_config.yaml.tmpl:79`;
  `home/.chezmoi.toml.tmpl` (host→headless/personal flags, unknown hosts
  default to headless=true, personal=false); `home/.chezmoiignore.tmpl`
  (existing per-OS conditionals); `docs/BITWARDEN.md` (classic `bw` session
  machinery — not the `bws` path); `docs/BASH_UPGRADE.md` §1 and §9 (headless
  nix-config shells deliberately token-less; `BWS_ACCESS_TOKEN` env fallback
  for CI/dev). Target path `~/.hermes/config.yaml` from
  `chezmoi target-path home/private_dot_hermes/private_config.yaml.tmpl`.
- **bws "Missing access token"** — observed output of the installed `bws`
  binary (reports the failure at `crates/bws/src/main.rs:65`); bws CLI
  repository is bitwarden/cli (crate `crates/bws`).
