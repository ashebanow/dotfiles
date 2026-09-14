# Findings bound to BOX-169 — the headless predicate's meaning for the file set

**Ticket:** [BOX-169](https://linear.app/boxbow/issue/BOX-169) (map: BOX-165, HEADLESS DOTFILES)
**Date:** 2026-09-12
**Method:** read-only inspection of this repo, the nix-config checkout, and lumquat
over SSH. No tracked file was modified except this document.

This is a fact bundle, not a decision. The three research tickets (BOX-166, BOX-167,
BOX-173) were re-derived from their branches into `docs/research/` here so the
predicate argument quotes the same evidence; their findings are **not** restated in
full, only the parts BOX-169 turns on.

---

## 1. New environment fact: the mealie quadlet is live and crash-looping on lumquat

BOX-167 judged `mealie.container` merely "correct-ish … no conflict". That is true
of *ownership*. The machine says something stronger:

```
$ systemctl --user show mealie.service -p UnitFileState -p WantedBy -p ActiveState
UnitFileState=generated
WantedBy=default.target
ActiveState=failed

$ systemctl --user status mealie.service
× mealie.service - Mealie Recipe Manager
     Loaded: loaded (/home/podman/.config/containers/systemd/mealie.container; generated)
     Active: failed (Result: start-limit-hit) since Sat 2026-09-12 11:27:03 PDT
    Process: 3904597 ExecStart=… podman run --name mealie … -v /srv/mealie:/app/data …
   Main PID: 3904597 (code=exited, status=125)

$ journalctl --user -u mealie.service | tail
Sep 01 17:56:58 lumquat mealie[…]: Error: statfs /srv/mealie: no such file or directory
Sep 12 11:27:03 lumquat systemd[1197]: mealie.service: Start request repeated too quickly.
Sep 12 11:27:03 lumquat systemd[1197]: mealie.service: Failed with result 'start-limit-hit'.

$ ls /srv
total 8   # empty; /srv/mealie does not exist
```

Facts worth separating:

1. The quadlet **is installed** as a generated user unit at
   `~/.config/containers/systemd/mealie.container`, and podman's own quadlet
   generator picks it up on every daemon reload. (The generator, not the unit, sets
   `WantedBy`; the source file's `[Install] WantedBy=multi-user.target default.target`
   still makes it `WantedBy=default.target` after generation.)
2. It **is being started on boot**. It has been failing since at least 2026-09-01 and
   was in `start-limit-hit` when inspected. It never reached a listening socket:
   `ss -ltn | grep 9925` is empty.
3. Nothing is serving on 9925 today, and `podman ps` shows only the
   nix-config-declared stacks (`bifrost`, `openwebui`, `memory`, `qwen-35b-a3b`).
4. The operator did not notice for six weeks, because a unit that only binds a
   socket and never reaches a working state is invisible: it is not error spam, it is
   a silent absence.

**Consequence for BOX-169:** the harm in a personal-server quadlet in `podman`'s home
is not a port clash — it is that a deleted/never-installed toy is *still an active
unit in this server's boot path*, without the server's operator knowing. Any predicate
that admits this file admits that.

## 2. Why the shape does not fall out of existing axes

| File | Excluded by "desktop"? | Excluded by "personal secret"? | Excluded by "tool absent"? |
|---|---|---|---|
| `systemd/user/sunset.service.tmpl` | no (a unit, not a GUI config) | no | no (`hypr/scripts/sunset.sh` is *itself* a sourced managed file — see §4) |
| `systemd/user/tmux.service` | no | no | **yes** (`tmux` absent, and `.config/tmux` is already excluded — this is the last tmux artefact) |
| `containers/systemd/mealie.container` | no | no | no (`podman` *is* tier-1) |
| `.config/devenv/config.yaml` | no | no | yes (devenv in no tier) |
| `.config/zennotes/config.toml` | no | no | yes |
| `.local/bin/mac_logout_handler.zsh` | **yes** (macOS tool) | no | yes |

Two of the three headline files survive every axis the map already has. That is the
gap BOX-169 exists to close.

## 3. Verified predicate facts (`home/.chezmoi.toml.tmpl:9-38`)

Headless is set true when: CODESPACES / REMOTE_CONTAINERS_IPC env, or
`username in {root, ubuntu, vagrant, vscode}`, or `os == windows`, or hostname in
`{lumquat, calamansi, kumquat, rangpur, tangelo}`, or non-TTY with no answer.

Headless is forced **false** (no prompt, no TTY requirement) on
`{bergamot, miracle_max, miraclemax, yuzu, liquidity-ubuntu-wsl, limon}`.

Consequences for any new predicate:

- **Dev machines are safe by name.** A new axis defaulting to "not this" on unknown
  hosts does not touch `bergamot`, `miracle_max`, `yuzu`, `limon`, or the WSL host —
  the personal list short-circuits before detection.
- **There is no prompt on macOS and no prompt on a known personal host**, so an
  interactive-only default is *reachable* on the two machines that matter, but only
  for a brand-new hostname.
- A BSD/Windows answer is not available: `home/.chezmoiscripts/` has only `darwin/`
  and `linux/` trees, and the only code-execution paths are the two scripts audited by
  BOX-166 (darwin-gated; linux hostname-gated, renders empty, exits 0).

## 4. The `~/.config/hypr/scripts/sunset.sh` detail the ticket's description assumed

The BOX-169 description says sunset.service "runs a Hyprland script". The source tree
says something worse for any pattern-based fix:

```
$ find home -path '*hypr*'
home/private_dot_config/hypr/scripts/sunset.sh          # a real, tracked source file
home/private_dot_config/hypr/scripts/…                  # the rest of the hypr tree
```

`~/.config/hypr/**` is excluded on headless by the ignore block, so
`~/.config/hypr/scripts/sunset.sh` **does not exist on lumquat** — the unit points at
a path that is absent *by our own exclusion*. It is a unit for a script we chose not
to ship, whose absence is correct.

This is the cleanest statement of the mis-classification: the desktop **axis** is
right; the sunset unit simply is not on it. The user unit lives in
`.config/systemd/user/`, which is not a desktop path, so no desktop pattern can ever
reach it.

## 5. `tmux.service` is also wrong on its own terms, independent of the predicate

```
ExecStart=/usr/bin/tmux new-session -s default -d
ExecStop=/usr/bin/tmux kill-session -t default
```

`/usr/bin/tmux` is an absolute path that exists on no NixOS host (NixOS has no
`/usr/bin`); even where the binary is present it lives in a store path or on PATH. So
the unit could silently fail to start while `systemctl --user is-enabled tmux.service`
still reports `disabled`/`static` and nothing surfaces. This unit should not survive on
*any* machine in this form; the predicate question is only whether it reaches headless.

## 6. Mechanism evidence that matters to the decision

- The headless ignore block renders **58 patterns** (`home/.chezmoiignore.tmpl:33-89`)
  and is a **denylist of remembered paths**. BOX-167 found two classes of defect born
  of that shape: patterns that match no real target (`.config/obsidian` vs
  `~/.config/.obsidian`, `.config/syncthingtray` vs `~/.config/syncthingtray.ini`) and
  trees no pattern mentions (`~/.config/YouTube Music/`, `~/.config/Code/User/`).
- Excluding a source file does **not** delete an already-provisioned target.
  `.chezmoiremove` is the mechanism for that (`home/.chezmoiremove`, currently 4
  entries, all `$HOME`-only) and is authorized by BOX-165 Q11a.
- `.chezmoiremove` **will** delete a file that is not managed on this machine class —
  it is not itself machine-gated. Any entry added there must be gated on the same
  predicate as the exclusion, or a personal machine will have the file deleted.
- `chezmoi destroy <target>` is the source-removal verb in 2.72; `chezmoi remove` is
  gone.
- Per BOX-166, the one abort-risk path on lumquat is
  `dot_pi/agent/extensions/linear/private_credentials.json.tmpl` calling `output "bws"`
  unguarded; the fix locked in charting is a guard, not an exclusion.
