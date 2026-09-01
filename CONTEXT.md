# CONTEXT — chezmoi dotfiles glossary

Terms used across this repo and its planning docs (wayfinder maps). Sharpened
2026-09-01 while charting the HEADLESS effort.

- **headless** — a machine interacted with only over SSH: no screen/keyboard,
  none of ashebanow's **personal secrets**, minimal toolset. Today headless ⊇
  remote: every remote machine is headless, so there is no separate `remote`
  axis (a future `remote` flag was discussed and deferred).
- **personal secret** — a secret tied to ashebanow's personal identity or
  accounts: SSH keys, GPG signing key, personal API keys (hermes, claude).
  Headless machines carry none of these; the `personal` *flag* is retired, but
  the concept lives as the file-gating predicate (`{{ if not .headless }}`
  excludes).
- **server secret** — a secret a server needs to operate: tailscale auth
  keys, DB passwords, service tokens. Headless machines *do* carry these;
  BWS is the secrets backend (nix-config delivers them via secretspec +
  bootstrap token → `LoadCredential`; chezmoi-managed files use chezmoi's
  built-in BWS).
- **personal machine** — a machine with the owner's interactive/desktop setup
  (macOS or desktop Linux). Used as shorthand for *not headless* when gating
  files; there is no `personal` data flag.
- **machine user / machine account** — a non-personal account on a server used
  to operate it (e.g. `podman` on lumquat). Dotfiles must work for it. The two
  terms are used interchangeably.
- **ephemeral** — *retired* flag for temporary cloud/VM instances. Its
  detection logic (containers, codespaces, generic cloud usernames) now feeds
  `headless` only.
- **shared shell layer** — the BASH_UPGRADE consolidation: one portable shell
  core shared by zsh and bash, with thin per-shell entrypoints. Machine-class
  differences are handled at file level (what a machine receives), not with
  shell branches.
