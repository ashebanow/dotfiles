# Global Agent Rules — Git & GitHub

These rules apply to all repositories unless a project's own `AGENTS.md`
explicitly overrides them (project rules win — e.g. a project that mandates
pushing at session end).

## Pushing — THE most important rule

**NEVER `git push` without explicit confirmation from me.**

- I often squash/reword local commits with `git rebase -i` before they go
  public. An early push makes that history rewriting painful.
- Committing locally is fine and encouraged; pushing is a separate,
  user-approved step.
- At the end of a work session, report any unpushed commits (hash + subject)
  and ask whether to push.
- Never force-push (`--force`/`--force-with-lease`) without explicit
  confirmation, even on branches you created.

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

- Use the `gh` CLI to inspect issues and PRs (`gh issue view N --repo
  owner/repo`, `gh pr view`), not web search.
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
