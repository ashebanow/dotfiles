# Issue tracker: Linear

Issues, specs, and tickets for this repo live in **Linear**, not GitHub.

- **Team**: Boxbow, key `BOX` (issue IDs look like `BOX-130`)
- **Project**: [Chezmoi](https://linear.app/boxbow/project/chezmoi-edbe1f926445)
- **Access**: the `linear` CLI ([schpet/linear-cli](https://github.com/schpet/linear-cli)) on
  PATH. Flags and subcommands live in the `linear-cli` skill (`~/.agents/skills/linear-cli`);
  invoke it when a recipe below is not enough. The recipes here are the ones this repo's
  skills need, verified against this workspace.

GitHub is used only for code (PRs against `ashebanow/dotfiles`). GitHub Issues are **not** a tracked
surface here; do not create or triage them.

## Auth

`linear auth whoami` must print `Workspace: Boxbow`. It authenticates from `LINEAR_API_KEY`;
there is no login step and no OAuth.

- **Darwin workstations**: the key is exported by `~/.config/shell/secrets.sh` (BWS cache,
  8 h). If `whoami` fails, open a fresh shell; if it still fails, `bws` or the keychain token
  is the problem, not Linear.
- **lumquat** (headless): the `linear` wrapper reads `/run/secrets/linear-api-key`, written at
  boot by `host-secrets-populate.service`. If `whoami` fails, check
  `systemctl status host-secrets-populate` and that the file is `0400 podman`. `linear auth
  login` is the wrong fix there — it needs a keyring the host does not have.

## Conventions

**Name the project on every write and every list.** `~/.config/linear/linear.toml` sets only
the team; the CLI has no project default. Pass `--project Chezmoi` to `issue create` and
`issue query`, and pass `--team BOX` to `issue query` (it warns otherwise).

Design decisions are recorded in the ticket body — treat the body as the spec. Markdown goes
through `--description-file` / `--body-file`, never inline `-d`/`-b`, so nothing is
shell-mangled.

| Operation | Command |
| --- | --- |
| Fetch a ticket | `linear issue view BOX-<n> --json` (fields: `description`, `state.name`, `labels.nodes[].name`, `parent`, `children.nodes[]`, `assignee`) |
| Read its history | `linear issue comment list BOX-<n> --json` (`.nodes[]`, newest first: `body`, `user`, `createdAt`) |
| List tickets | `linear issue query --team BOX --project Chezmoi --state unstarted --state started --json --limit 0` — `--state` takes state **types** (`triage`, `backlog`, `unstarted`, `started`, `completed`, `canceled`), never names; repeat it to union |
| Create a ticket | `linear issue create --no-interactive --project Chezmoi --title "…" --description-file body.md` (`--label <name>` repeatable; `--parent BOX-<n>` for a sub-issue; `--state Todo`) |
| Comment | `linear issue comment add BOX-<n> --body-file note.md` |
| Labels | `linear issue update BOX-<n> --add-label "Ready For Agent"` / `--remove-label …` (by name; `--label` *replaces* the whole set). Inventory: `linear label list` |
| Change state | `linear issue update BOX-<n> --state "In Progress"` (by name; `linear team states` lists them) |
| Close | `linear issue update BOX-<n> --state Done` — or `Canceled` / `"Won't Fix"` / `"Can't Reproduce"` / `Duplicate`, with a comment saying why |
| Claim / assign | `linear issue update BOX-<n> --assignee self` (`--unassign` to release) |
| Block | `linear issue relation add BOX-<a> blocked-by BOX-<b>` (also `blocks`, `related`, `duplicate`); `linear issue relation list BOX-<a>` to inspect |
| Anything else | `linear api` with a heredoc GraphQL query (`linear schema` for the types) |

**Labels and states.** The workspace labels are `Ready For Agent`, `Deferred`, `Feature`,
`Bug`, `Improvement`, plus the team's `wayfinder:*`. Triage roles map through
`docs/agents/triage-labels.md` — four of the five have no label because Boxbow models triage
in workflow **states**: `Backlog`, `Icebox`, `Todo`, `In Progress`, `In Review`, `Ready to
Merge`, `Done`, `Canceled`, `Won't Fix`, `Can't Reproduce`, `Duplicate`. Prefer a state where
one matches; use labels only for roles with no matching state.

## When a skill says "publish to the issue tracker"

`linear issue create --no-interactive --project Chezmoi --title "…" --description-file …`.
For a set of tickets, create blockers first so each `relation add` can name a real id.

## When a skill says "fetch the relevant ticket"

`linear issue view BOX-<n> --json`, then `linear issue comment list BOX-<n> --json` when the
conversation history matters.

## Blocking / dependencies

Linear models these as **issue relations**; use `relation add … blocked-by …`. A ticket is
unblocked when every blocker is in a `completed` or `canceled` state — read that from the
`inverseRelations` of the frontier query below, not from a `Blocked by:` line.

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue; **child** tickets are its Linear sub-issues.

- **Map**: an issue with the `wayfinder:map` label holding the Notes / Decisions-so-far / Fog
  body. `linear issue view BOX-<map> --json` lists its children under `children.nodes[]`
  (identifier, title, state name).
- **Child ticket**: `linear issue create --no-interactive --project Chezmoi --parent
  BOX-<map> --label wayfinder:<type> --title "…" --description-file …` with `<type>` one of
  `research` / `prototype` / `grilling` / `task`.
- **Blocking**: `linear issue relation add BOX-<child> blocked-by BOX-<other>`.
- **Frontier query** — open, unblocked, unclaimed children, in one call:

  ```sh
  linear api --variable id=BOX-<map> <<'GRAPHQL'
  query($id: String!) {
    issue(id: $id) {
      children { nodes {
        identifier title
        state { type name }
        assignee { displayName }
        inverseRelations { nodes { type issue { identifier state { type } } } }
      } }
    }
  }
  GRAPHQL
  ```

  A child is on the frontier when `state.type` is `unstarted`/`started`/`backlog`/`triage`,
  `assignee` is null, and no `inverseRelations` node has `type == "blocks"` with an `issue`
  whose `state.type` is outside `completed`/`canceled`. `children.nodes` comes back newest
  first; map order is the reverse, so take the *last* frontier match.
- **Claim**: `linear issue update BOX-<child> --assignee self --state "In Progress"` — the
  session's first write.
- **Resolve**: `linear issue comment add BOX-<child> --body-file answer.md`, then
  `linear issue update BOX-<child> --state Done`, then append a context pointer to the map's
  Decisions-so-far (`linear issue update BOX-<map> --description-file map.md` with the edited
  body from `issue view --json`).
