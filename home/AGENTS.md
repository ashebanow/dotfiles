# Global Agent Rules — Git & GitHub

These rules apply to all repositories unless a project's own `AGENTS.md`
explicitly overrides them (project rules win — e.g. a project that mandates
pushing at session end).

## Pushing

**Feature branches: commit AND push freely. No confirmation needed.**

Once work is on a branch you created, pushing it is routine — that's what
branches are for. Don't stop to ask.

**Ask first for exactly two things:**

1. **Anything that touches `main`** — direct commits or pushes to `main`, and
   merges into it.
2. **Opening or updating a PR.** Drafting the branch is free; publishing it
   for review is the approval step.

**Never, ever, without explicit confirmation:**

- `git push --force` / `--force-with-lease`, on any branch, including yours.
- Rewriting history that has already been pushed (e.g. `git rebase -i` on a
  branch with a PR). Local squashing before pushing is fine — that's exactly
  why an unwanted early push is costly.

At session end, still report the branch and its commits so the state is clear.

## Commits

- Follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `chore:`, `docs:`, `test:`, `refactor:`, `ci:`, etc.
  Several of my repos use release-please, so the type prefix has release
  semantics — don't guess; `fix:`/`feat:` cut releases, `refactor:`/`test:`
  and friends do not.
- Keep commits small and focused: one logical change per commit.
- Write a body explaining *why* when the change isn't self-evident.
- When a commit addresses a GitHub issue, include `fixes #N` / `resolves #N`
  (auto-close) or `refs #N` (link only) in the body.
- Stage specific files (`git add <paths>`); avoid `git add -A` unless you
  have verified everything in `git status` belongs in the commit.

## Branches & history

- `main` is stable. Do non-trivial work on feature branches and test before
  merging to main.
- Prefer linear history: rebase over merge commits unless the project says
  otherwise.
- Never rewrite history that has already been pushed without explicit
  confirmation.

## GitHub

- **Issues live in Linear, not on GitHub.** Use the `linear` CLI (`linear issue
  view BOX-123`, `linear issue list --team BOX`) — never `gh issue`, and never
  web search. GitHub is code-only: PRs, branches, releases.
- A "GitHub issue" in the commit-message convention below is usually a Linear
  reference in practice; put the Linear ID (`BOX-123`) in the commit body.
- Use `gh pr view` / `gh pr list` for pull requests.
- Don't merge, close, or comment on PRs/issues without being asked.

## Secrets & hygiene

- Never commit secrets, tokens, or credentials. Use the project's secret
  mechanism (chezmoi + Bitwarden templating, encrypted `.env.enc`, secretspec,
  etc.).
- If a file looks like it contains generated credentials or private keys,
  stop and ask before staging it.
- Don't commit generated artifacts, caches, or editor droppings unless the
  project explicitly tracks them.

## Safety

- Never run destructive git commands (`reset --hard`, `clean -fd`,
  `checkout -- .`, branch deletion) on uncommitted work without confirmation.
- If a rebase/merge conflict appears mid-operation, pause and summarize
  rather than resolving blindly.
