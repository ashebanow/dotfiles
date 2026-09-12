# The headless file set is decided by a positive rule, not a denylist

Status: accepted (2026-09-12, BOX-169)

The `headless` machine class excludes whole files from the target home, and until
now it decided membership with a denylist of remembered paths in
`home/.chezmoiignore.tmpl`'s `{{ if .headless }}` block. That block's failures
were structural rather than clerical: patterns that matched no real target
(`.config/obsidian` vs the actual `~/.config/.obsidian`, because chezmoi strips
the source's leading `dot_`) and trees no pattern mentioned at all
(`~/.config/YouTube Music/`, `~/.config/Code/User/`) shipped to the server for
months. A denylist cannot express "this tree simply isn't this machine's job",
so absence from the list reads as inclusion.

We decided the file set is membership by a **positive rule**: a managed file is
kept iff the tool it configures is installed on this host, at any tier —
`environment.systemPackages`, `home.packages`, or the `nix develop` devshell.
The check is the nix-config tool inventory, not a remembered list. The negation
binds too: a file whose tool is absent at every tier is wrong, whether or not it
looks desktop-shaped.

## Considered options

**Broaden `headless` to also mean "no personal-server toys and no
desktop-service units".** Rejected: it would make one flag carry three
unrelated axes — no screen/keyboard, not a desktop host, and not the owner's
personal machine — and the first file to disagree with any one of them would
force the flag to be re-litigated.

**Fix each file individually.** Rejected as the *whole* answer: it repairs the
current offenders without preventing the next one, which is exactly how the
denylist produced two defect classes in one pass.

**Per-tool ownership manifests.** Rejected: cross-repo coupling that rots, as
`install-headless.sh` already demonstrated.

## Consequences

- **`desktop` becomes its own term**, independent of `headless`. Gating a
  display feature on `not .headless` is an accident that has already happened
  once (`sunset.service`, whose `ExecStart` points into `.config/hypr/**` — a
  tree the ignore block excludes, so the unit targets a path absent by our own
  decision).
- **The exception channel is "not this server's job"**, for a personal toy that
  passes the installed-tool rule because its *runtime* is installed (`podman`
  is installed; a recipe-manager quadlet is still not the server's job).
  Recorded per file, not as a `personal` data flag — nothing would consume such
  a flag today, and a flag no file reads is a denylist waiting to happen.
- **Retirement has a bar.** `chezmoi destroy` is reserved for provable
  breakage — broken on this machine class, or broken on every machine —
  because exclusion is one reversible line of `.chezmoiignore` while `destroy`
  is not. Applied: `tmux.service` (its `ExecStart=/usr/bin/tmux` exists on no
  NixOS host) and `mealie.container` (never worked; `/srv/mealie` absent since
  at least 2026-09-01) are destroyed; `sunset.*` is excluded.
- **`.chezmoiremove` is not machine-gated.** Any entry mirroring an exclusion
  must carry the same predicate, or applying on a personal machine deletes the
  file there.
- **Two rules about branching, kept distinct.** Machine-class gating *prefers*
  the file level but permits an in-file conditional where the file must stay
  managed on the excluded class (the `~/.pi` credentials guard). The shared
  shell layer admits no branches on the prompt hotpath, because a branch there
  costs a subshell fork — a latency rule with no purchase off the hotpath.
