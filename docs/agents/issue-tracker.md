# Issue tracker: Linear

Issues, specs, and tickets for this repo live in **Linear**, not GitHub.

- **Team**: Boxbow (issue IDs look like `BOX-130`)
- **Project**: [Chezmoi](https://linear.app/boxbow/project/chezmoi-edbe1f926445)
- **Access**: the `linear-server` MCP (`mcp__linear-server__*` tools), or pi's `linear_*` tools.
  OAuth-gated — if the tools are unavailable, run `mcp__linear-server__authenticate`, hand the
  user the URL, and wait for them to finish before retrying.

GitHub is used only for code (PRs against `ashebanow/dotfiles`). GitHub Issues are **not** a
tracked surface here; do not create or triage them.

## Conventions

- **Fetch a ticket**: `get_issue` with the identifier (`BOX-130`). Read its description and,
  when history matters, `list_comments`. Design decisions are recorded in the ticket body —
  treat the body as the spec.
- **List tickets**: `list_issues`. **Observed caveat (2026-09-11):** passing `projectId` did
  not filter — a query scoped to the Chezmoi project returned Nix-Config issues. Filter on
  `project.name` in the results; don't assume a projectId filter applied.
- **Create a ticket**: `create_issue` with team Boxbow, project Chezmoi, a title, and a
  Markdown description. Set the parent for a sub-issue.
- **Comment**: `create_comment` with the issue id and a Markdown body.
- **Labels**: `update_issue` with label ids. The workspace labels are `Ready For Agent`,
  `Deferred`, `Feature`, `Bug`, `Improvement`, plus the team's `wayfinder:*`. The canonical
  triage roles map through `docs/agents/triage-labels.md` — four of the five have no label.
- **Triage state**: prefer a real workflow **state** where one matches — `Backlog`, `Icebox`,
  `Todo`, `In Progress`, `In Review`, `Ready to Merge`, `Done`, `Canceled`, `Won't Fix`,
  `Can't Reproduce`, `Duplicate`. Use labels only for roles with no matching state.
- **Close**: `update_issue` to a completed state (`Done`, or `Canceled` / `Won't Fix`); add a
  `create_comment` explaining why when closing without completing the work.

## When a skill says "publish to the issue tracker"

Create a Linear issue with `create_issue` under team Boxbow, project Chezmoi.

## When a skill says "fetch the relevant ticket"

`get_issue` on the identifier the user gave (`BOX-<n>`), then `list_comments` if the
conversation history is relevant.

## Blocking / dependencies

Linear models these as **issue relations** (`blocks` / `blocked by`). Set them with the
relation tools. Where that isn't available, fall back to a `Blocked by: BOX-<n>, BOX-<n>` line
at the top of the description. A ticket is unblocked when every blocker is in a completed state.

## Wayfinding operations

Used by `/wayfinder`. The **map** is one issue; **child** tickets are its Linear sub-issues.

- **Map**: an issue with the `wayfinder:map` label holding the Notes / Decisions-so-far / Fog body.
- **Child ticket**: a sub-issue (parent = the map) with the question in the body. Label
  `wayfinder:<type>` (`research` / `prototype` / `grilling` / `task`). Assign on claim.
- **Blocking**: issue relations as above, else a `Blocked by:` line in the child body.
- **Frontier query**: `list_issues` scoped to the map's children, state = not-started or
  started; drop any with an open blocker or an assignee; first in map order wins.
- **Claim**: `update_issue` assigning the issue to the current user — the session's first write.
- **Resolve**: `create_comment` with the answer, `update_issue` to a completed state, then
  append a context pointer to the map's Decisions-so-far.
