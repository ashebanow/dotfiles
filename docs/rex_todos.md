# Rex: switching from the downloaded app to the nix flake

Current state on miraclemax: Rex is installed manually as
`/Applications/Rex Beta.app`. The plan is to replace that with the flake's
`my.rexClient` flag. This file records what that means and what to check.

This is separate, later work — nothing here is needed for `~/.ssh/config` to
be correct today.

## The nix side already exists

`modules/features/rex.nix` in nix-config already provides the client path, and
`my.rexClient = true` is already set for miraclemax, yuzu, and bergamot
(`hosts/*/capabilities.nix`). See `docs/rex.md` in that repo.

So switching away from the app is a matter of:

1. Building with the flake (`darwin-rebuild switch` / `nh darwin switch`) and
   confirming `rex` resolves to the nix store rather than the app bundle.
2. Removing `/Applications/Rex Beta.app` once the flake build is confirmed, so
   a stale bundle cannot shadow the nix binary.

## No activation script is needed for `rex terminfo setup`

`programs.rex.enable = true` (which `my.rexClient` turns on) already installs
the `rex` command and the `xterm-rex` terminfo entry. There is no need for a
hand-rolled `home.activation` snippet calling `rex terminfo setup`.

## The ssh guard is chezmoi's job, by design

`modules/features/rex.nix` deliberately does **not** set `programs.ssh.enable`:

> `programs.ssh.enable` is also not set here: the Rex modules add their guard
> to `programs.ssh.includes`, and `~/.ssh/config` is chezmoi's on these hosts.
> Setting it would have Home Manager and chezmoi write the same file in turn.
> The module prints a warning instead; the dotfiles repo carries the guard.

That warning is expected on these hosts and is not a fault. The guard lives in
`home/private_dot_ssh/private_config.tmpl`:

```
Include "{{ .chezmoi.homeDir -}}/.config/rex/ssh_config"
```

It must stay at the very top of the rendered `~/.ssh/config`:

- the guard is a `Match` block, and ssh only honours `Match` before the first
  `Host` block;
- ssh keeps the earliest value for a setting, so `SetEnv TERM` must precede
  `Host *`.

Rex owns `~/.config/rex/ssh_config` and rewrites it. It is deliberately **not**
a chezmoi target — see "Do not template it" below.

## Verification after the first nix-managed switch

```shell
command -v rex                  # expect a /nix/store path, not the app bundle
rex terminfo status
```

Expect:

- `term: xterm-rex (the entry is installed and the ssh guard is active)`
- `guard: ~/.config/rex/ssh_config is current`
- `include: not needed, because ~/.ssh/config already includes a guard`

Then confirm ssh still parses the config, and that chezmoi agrees:

```shell
ssh -G github.com >/dev/null && echo "ssh config OK"
chezmoi status ~/.ssh/config    # expect: no output
```

## Notes and gotchas

- `~/.config/rex/terminfo-hosts` is **not** written by `rex terminfo setup`.
  It is created lazily as Rex learns which hosts have the `xterm-rex` entry.
  The guard tolerates its absence (`grep ... 2>/dev/null`), so a missing file
  is normal, not a fault.
- The guard file must not be group- or world-writable. ssh refuses such a file
  ("Bad owner or permissions") and drops the guard.
- Bump the flake input with `nix flake update rex` when a newer release ships
  (see the comment beside `rex.url` in `flake.nix`).

## Do not template `~/.config/rex/ssh_config`

Considered and rejected. Rex explicitly owns and rewrites that file, and
templating it would:

- put two writers back on one file (the exact problem that made
  `~/.ssh/config` fragile in the first place);
- freeze the guard's quoting-sensitive `/bin/sh` predicate at whatever version
  was templated, so upstream fixes would never reach any machine;
- make `rex terminfo status` report on a file Rex did not write.

The per-machine cost of leaving it to Rex is one idempotent command that
`programs.rex` already covers.

## Related

- lazyssh was removed from nix-config (`ff2a96c chore(cli): drop lazyssh`)
  because it rewrote `~/.ssh/config` from its own internal model and silently
  dropped the guard `Include` and chezmoi's rendered comments.
