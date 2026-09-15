---
name: afk-loop
description: "Autonomous pickup-to-merge pipeline for ready-for-agent issues: estimates unscored issues, works the queue easiest-and-highest-priority first, and runs each one through an isolated TDD implementor and an independent, self-verifying code-review loop until it converges to a squash-merge or needs a human. Use when the user asks to work through the backlog unattended, clear the ready-for-agent queue, or run the AFK loop."
argument-hint: "Optional: a specific issue ID to run through the loop alone, instead of the whole ready-for-agent queue"
disable-model-invocation: true
---

# AFK loop

Runs `ready-for-agent` issues end to end — estimate, implement, review, merge — with **you as orchestrator only**. You build the queue, spawn agents, and act on their verdicts; you never judge code quality or test correctness yourself. That judgment belongs to the reviewer subagent, on purpose (see "Why the orchestrator doesn't verify" below).

## Step 0 — read the repo config

This skill is repo-agnostic. Every repo-specific value comes from a config file, resolved in this order:

1. **`.afk.toml` at the repo root** — the normal case; the repo owns its settings.
2. **`afk.default.toml`, in this skill's own directory** — the fallback. Its values are the safe ones: no App, reviews as comments, merge left to a human.

Read the config before doing anything else, and take every repo-specific value from it:

| Section | What it gives you |
|---|---|
| `[repo]` | `slug` (`owner/name`, for `gh api` paths), `never_commit` globs |
| `[identity]` | `author` — the `gh` account the loop authors PRs as; `commit_magic` — the tracker magic word |
| `[app]` | the App for unattended review/merge: `name`, `script`, `mint`, `setup_doc` |
| `[review]` | `as` = `app`\|`user`; `fallback` when minting fails |
| `[merge]` | `as` = `app`\|`user`; `strategy`; `delete_branch` |
| `[tracker]` | `kind` = `linear`\|`github`; `doc`; `labels_doc`; `ready_label` |
| `[worktree]` | `sibling`; `symlink_node_modules`; `doc` |
| `[skills]` | the umbrella skills the personas lean on |

**If the repo has no `.afk.toml`, say so before you start.** The loop will run without an App, reviews land as plain comments, and every merge needs a human. That is a degraded mode, not a failure — name it up front rather than silently discovering it at the merge step.

Consult the tracker's `doc` for how to read and write the tracker, and `labels_doc` for how the canonical triage roles map onto this tracker's real labels and states. If either is absent, work from the tracker's own CLI or UI, and state the assumption you made.

## The two personas

The implementor and reviewer roles are fixed personas with their model and effort pinned declaratively, not re-typed into a prompt each time. Both live in the **base harness**, so they are available in every repo:

- **Claude Code**: `~/.claude/agents/afk-implementor.md` and `afk-reviewer.md`. Spawn them by `subagent_type` name (`afk-implementor` / `afk-reviewer`). Their frontmatter pins `model` and `effort`; their body is the full persona. **New or edited agent files only take effect in a fresh session** — if a `subagent_type` lookup fails with "not found" mid-session, a persona file changed since this session started; fall back to a `general-purpose` subagent with an explicit `model` override, pasting that file's body in as the system-prompt portion of the launch prompt, and tell the user a session restart will re-enable spawning it by name.
- **pi**: `~/.pi/agent/agents/afk-implementor.md` and `afk-reviewer.md`, loaded by the subagent extension. Spawn them the same way, by `subagent_type` name. pi has no `effort` field — the equivalent is `thinking`, already set in the file.

  **pi caveat — pass `model` explicitly on every spawn.** pi resolves an agent file's `model:` only when it is written `provider/modelId` *and* that pair is present and authenticated in the registry; anything else — most importantly a bare id — falls through and runs the subagent on **your** model, with no warning. The per-call `model` parameter does not have that failure mode: it resolves fuzzily, accepts a bare id, and fails loudly with the available list when it cannot match. So on pi, treat the agent file's `model:` as a declaration of intent and pass `model` on the call as the thing that actually takes effect. This is also how you size the model to the issue's estimate, as 4c asks.

Both harnesses generate their copies from one source: the personas' prose lives once, at `~/.agents/skills/afk-loop/personas/*.body.md`, and each harness's file is a thin frontmatter cover sheet over that shared body. If a persona needs to be read directly (for instance when falling back to `general-purpose`), read the `.body.md` file — it is runtime-agnostic and carries no frontmatter.

Either way, only the **per-issue variable content** below goes in the launch prompt itself — the fixed rules (TDD discipline, definition of done, verification duties, output format) live in the persona file, edited in one place. Always spawn with **no prior context**: the personas must not inherit this conversation.

## Process

### 1. Build the queue

List every issue that is **open and ready**, carrying the config's `ready_label`, in the status your `labels_doc` maps to "ready to start" (for a Linear-backed repo that is normally the **Todo** status; for GitHub Issues it is the open issue with that label). Every other label is irrelevant to membership: bug, feature, improvement, and chore all qualify equally.

If the user passed a specific issue ID as an argument, skip straight to step 4 with just that issue.

### 2. Estimate what's unscored

For any queue issue with no estimate set, score it on a binary exponential curve:

| Points | Meaning | Rough duration |
|---|---|---|
| 1 | Trivial | ≤ 10 minutes |
| 4 | Average | ≤ 1 hour |
| 8 | Tough | ≤ 2 days |
| 16 | Mega | > 2 days |

Base the score on the issue's actual content: a precise, fully-specified change with a written test checklist is small; an issue with open design questions, unresolved tradeoffs, or "not decided yet" discussion in its own description is large regardless of how few files it touches — ambiguity to resolve is part of the work. Write the estimate back to the tracker immediately so a re-run doesn't redo this step.

### 3. Order and filter

Sort the queue by estimate ascending, then by priority descending (highest priority first) as a tiebreak. Drop every issue estimated **8 or more points** from the working queue — flag them to the user as skipped (too large for unattended work) rather than silently dropping them.

### 4. Work the queue, one issue at a time

Do not parallelize across issues — finish one issue's full cycle (through merge or hand-off) before starting the next. Within one issue, the steps below run in order.

#### 4a. Claim

Move the issue to the tracker's "in progress" state (Linear: **In Progress**; GitHub Issues: leave it open and say you are working on it in a comment).

#### 4b. Isolate

Create a git worktree per the config's `[worktree]` block, honoring both of its booleans. With `sibling = true` (the default) it goes as a **sibling** of the checkout, never nested inside it — that is the usual repo convention, documented at `[worktree] doc`, and where the repo states it, it is a hard convention rather than a suggestion: `git worktree add ../<short-name> -b <branch>`. With `symlink_node_modules = true`, symlink `node_modules` in from the primary checkout rather than reinstalling. This worktree is the implementor's entire world for this issue.

#### 4c. Implement (fresh `afk-implementor`, TDD)

Spawn the implementor persona (see "The two personas") with **no prior context** — it must not inherit this conversation. The launch prompt carries only what is per-issue: the full issue text (title, description, acceptance criteria if any), the worktree path and branch name, and — on a fix round — the reviewer's numbered fix list. Size the persona's model/effort to the issue's estimate at spawn time if your runtime lets you override it per call; a 4-point issue doesn't need the same depth as an 8-point one.

When it reports back, treat its self-reported "tests pass" as a **claim**, not a fact — the review loop (4d) verifies it independently. Move the issue to the tracker's review state once the PR is open.

#### 4d. Review loop (fresh, independent `afk-reviewer` rounds)

This is a bounded loop, **maximum 10 rounds total** (an implementor-fix plus a reviewer counts as up to 2 agents per round). Each round spawns fresh subagents with no memory of prior rounds and no access to each other's reasoning — the reviewer in particular must be independent of the implementor, seeing only the diff, the ticket, and the repo, never the implementor's chain of thought. This independence is the point: a reviewer that inherited the implementor's framing would rubber-stamp the implementor's own blind spots.

Communicate between rounds through the **PR itself** — `gh pr review` / `gh pr comment` — rather than an ad hoc side-channel file. It's durable, auditable by the human at any time mid-loop, and it's exactly what a human reviewer would leave for a human implementor to act on.

**Who posts the review, and why it is usually an App.** GitHub refuses an approve or request-changes from the PR's own author as self-review, and the loop authors PRs as `[identity] author`. Reviewing as that same account therefore degrades to a comment. When the config sets `[review] as = "app"`, the reviewer authenticates as `[app] name` — a separate principal — so its review is accepted and the PR gets a real approval rather than a comment. The reviewer persona owns the mechanics; the merge step (4e) authenticates as the **same App**, because it is the App that holds the ruleset bypass, so its merge is accepted where the author's own identity would be refused.

When `[review] as = "user"`, skip the App entirely and post as the author, accepting that the formal review state will be a comment.

If the App isn't provisioned on this machine (`Secret 'X' is required but not set`), the reviewer falls back per `[review] fallback` — normally `--comment` with its verdict at the top. That's a degraded mode, not the design: it means no PR can be merged unattended until a human runs the setup wizard in `[app] setup_doc`. Surface it rather than quietly living with it.

Each round:

1. Spawn the reviewer persona with the PR URL/number, the worktree path, and the full issue text (including what's explicitly in vs. out of scope, so the reviewer judges against the accepted bar rather than every idea the ticket's discussion raised). It reports back one of two verdicts plus, if changes are requested, a concrete numbered fix list a cold agent could act on.
2. If **APPROVE** and the suite is verified green: go to 4e.
3. If **REQUEST_CHANGES**: spawn a fresh implementor persona (no memory of the prior round) with the PR URL, the reviewer's fix list, and the same worktree. It addresses every item, re-verifies its own typecheck/suite, pushes to the same branch, and reports back. Loop to step 1.
4. If the round budget (10) is exhausted without an APPROVE: stop. Leave the PR open, leave the issue in the review state, and tell the user this issue didn't converge and needs their attention. Do not merge. Move to the next queue issue.

#### 4e. Converge

On a verified APPROVE with a green suite, merge the PR. **Exactly one merge path applies**, chosen by `[merge] as`:

**`as = "app"`** — merge as the App, not as yourself, for the same reason the review runs as the App, plus the ruleset bypass: the App is a bypass actor on the base branch's ruleset (see `[app] setup_doc`), so its merge is accepted where the author's own identity would be refused. Mint a token and merge in one step, from the repo root, expanding `[app] mint` with `{phase}` = `merge` and `{script}` = `[app] script`:

```
GH_TOKEN=$(<expanded mint command>) \
  gh pr merge <n> --<[merge] strategy> --delete-branch=<[merge] delete_branch>
```

Three parts of that command are load-bearing:

- The mint command's own required flags are mandatory — if it needs a `--reason`, an explicit provider, or similar, omitting it makes the provider refuse.
- The token exists **only inside that command's environment**, so `GH_TOKEN=$(...)` must be on the same invocation as the `gh` call. Exporting it in a separate step will not carry over.
- Invoke the App's script as `bash <script>`, not bare `<script>` — executing it by path has been intercepted by a terminal emulator's shebang-confirmation feature, opening a blocking GUI dialog nobody is present to dismiss and hanging the round indefinitely.

The App's merge can be accepted only when the App is a bypass actor on the base-branch ruleset **and** holds `Contents: write` plus `Pull requests: write` on the repo (merging needs contents write; posting reviews needs only pull-request access). Both are one-time provisioning, documented in `[app] setup_doc`.

**`as = "user"`** — do not merge. Stop after the verified APPROVE, leave the PR open, tell the user the PR is approved and green and waiting on them, and move to the next queue issue.

**Fallback, either way:** if the token mint fails (`Secret 'X' is required but not set`, or a sandbox refusing `api.github.com` / the secret store), or the ruleset isn't set up yet so GitHub refuses the App's merge ("the base branch policy prohibits the merge"), then do **not** hunt for a way around it — no `--admin`, no bypass wrangling — without explicit say-so. Merge with your own identity only if you are permitted to, and surface the situation: the loop needs human confirmation before it can close issues unattended. That confirmation is expected friction, not a failure.

Then remove the worktree and branch yourself so cleanup is deliberate: `git worktree remove <path>` and `git branch -d`/`-D` per the repo's worktree convention. A squash-merged branch reports "not fully merged" and needs `-D` — that is expected, not a sign anything is wrong. The tracker issue typically closes automatically from the merge's magic-word link; confirm it landed in the tracker's done state and transition it manually if the automation didn't fire.

Then continue to the next issue in the ordered queue (step 4).

## Why the orchestrator doesn't verify

You hold the full picture across every round, which makes it tempting to eyeball a diff or a "tests pass" claim and move on. Don't — that collapses the independence the loop is built on. The reviewer subagent exists specifically so a genuinely fresh set of eyes, with no stake in the implementor's framing, checks the work; the orchestrator second-guessing that with its own read defeats the separation and lets an orchestrator-level blind spot slide through unchecked. If a subagent's report looks internally inconsistent, that's a reason to route it back into the loop for the reviewer to confirm — not to adjudicate it yourself.
