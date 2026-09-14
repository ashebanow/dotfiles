# CONTEXT — chezmoi dotfiles glossary

Terms used across this repo and its planning docs (wayfinder maps). Sharpened
2026-09-01 while charting the HEADLESS effort.

- **headless** — a machine interacted with only over SSH: no screen/keyboard,
  none of ashebanow's **personal secrets**, minimal toolset. Today headless ⊇
  remote: every remote machine is headless, so there is no separate `remote`
  axis (a future `remote` flag was discussed and deferred). Headless is *not*
  a synonym for "no desktop" — that is its own term (**desktop**) — and it is
  not "not ashebanow's machine" either (BOX-169).
- **desktop** — a host with a graphical session: a screen someone actually
  logs into. Independent of **headless**: a headless desktop host (a server
  with a monitor nobody uses) is possible in principle, so gating a display
  feature on `not .headless` is an accident waiting to happen. No data flag
  exists yet; `sunset.service`/`sunset.timer` are its first consumers.
- **installed-tool rule** — the positive form of the file-set predicate: a
  managed file is kept iff the tool it configures is installed on this host,
  at any tier including the `nix develop` devshell. The check is the
  nix-config tool inventory, never a remembered list. Its negation binds too:
  a file whose tool is absent at every tier is wrong, desktop-shaped or not.
  **Exception:** "not this server's job" overrides it for a personal toy
  (BOX-169 Q1b), recorded per file rather than as a flag.
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
- **personal machine** — a machine that is ashebanow's own, as opposed to one
  he provisions. Used as shorthand for *not headless* when gating files; there
  is no `personal` data flag, and BOX-169 declined to mint one (nothing would
  consume it — the installed-tool rule's exception channel covers the cases).
  Distinct from **desktop**, which is about the host having a graphical
  session rather than about who owns it.
- **machine user / machine account** — a non-personal account on a server used
  to operate it (e.g. `podman` on lumquat). Dotfiles must work for it. The two
  terms are used interchangeably.
- **ephemeral** — *retired* flag for temporary cloud/VM instances. Its
  detection logic (containers, codespaces, generic cloud usernames) now feeds
  `headless` only.
- **shared shell layer** — the BASH_UPGRADE consolidation: one portable shell
  core shared by zsh and bash, with thin per-shell entrypoints. Two separate
  rules govern how it splits, and they must not be conflated (BOX-169 Q9):
  - **Machine-class gating prefers the file level** — a distinct file per
    machine class beats an in-file conditional. An in-file conditional is
    legitimate where the file must stay *managed* on the excluded class (the
    `~/.pi` credentials guard). Branching is not banned (BOX-169 Q3).
  - **Prompt-path overhead admits no branches** — nothing on the shell-startup
    or per-prompt hotpath may branch, because a branch there costs a subshell
    fork. This is a latency rule, not a correctness or portability rule, so it
    has no purchase off the hotpath (a template conditional evaluated once per
    `chezmoi apply` is not on it).
