# ~/.agents/skills — user-level agent skills

Skills every agent on this account should see, regardless of repo. Deployed
by chezmoi from `home/dot_agents/skills/`.

Who reads this directory:

- **pi** scans `~/.agents/skills/` natively — nothing else to wire.
- **Claude Code** does not; it reads `~/.claude/skills/`, so a chezmoi-managed
  skill here needs a relative symlink there (`home/dot_claude/skills/symlink_<name>`
  → `../../.agents/skills/<name>`). Note `~/.claude` is excluded on headless
  hosts, so Claude Code there sees none of these; pi still does. The Matt
  Pocock set is the exception (see below) — Claude Code gets it from a plugin,
  so it has no symlinks here.
- `npx skills add …` (skills.sh) also installs into this directory and tracks
  its own entries in `~/.agents/.skill-lock.json`; chezmoi-managed skills are
  not in that lock and must not be `npx skills`-updated.

Vendored third-party skills carry a `VENDORED.md` with tag and provenance and
a `just` recipe that refreshes them (see the repo justfile); never hand-edit.
First-party skills are the opposite — see below.

## Three provenance categories

Everything here is one of these. Know which before editing anything:

| Category | Example | Rule |
|---|---|---|
| **First-party** | `afk-loop` | Authored here. Edit freely — see below. |
| **Vendored** | `linear-cli` | Has `VENDORED.md` + a `just` refresh recipe. Never hand-edit. |
| **Bulk-vendored** | the Matt Pocock set | Provenance in the repo-root `skills-lock.json`. Never hand-edit; refresh as a set. |
| **npx-managed** | `find-skills` | Installed by `npx skills`; tracked in `~/.agents/.skill-lock.json`, not by chezmoi. |

The "never hand-edit" rule below applies to the vendored categories only.
Applying it to a first-party skill would be wrong — those are yours to change.

## First-party skills

Skills this repo authors rather than vendors, currently `afk-loop`. They are
edited here directly and take effect on the next `chezmoi apply`.

A first-party skill may deploy more than the one directory. `afk-loop` also
owns generated per-harness agent files (`home/dot_pi/agent/agents/`,
`home/dot_claude/agents/`) whose prose lives once in the skill's
`personas/*.body.md` and is stapled under a harness-specific frontmatter cover
sheet by a chezmoi template. Edit the `.body.md`, never the generated file.

Note the two harnesses need genuinely different frontmatter — pi reads
`thinking:` and lowercase builtin tool names with no Skill tool, Claude reads
`effort:` and capitalised names including Skill — so the split cannot be
collapsed into one shared file or a symlink.

Also note: an agent file's `model:` is resolved differently on each harness.
On pi it *silently* falls back to the orchestrator's model unless the value is
a `provider/modelId` pair present and authenticated in the registry, which is
why `afk-loop`'s SKILL.md tells the orchestrator to pass `model` per call.

## The Matt Pocock engineering skills

The 37-skill [Matt Pocock engineering set](https://github.com/mattpocock/skills)
lives here as a bulk vendored drop. It does **not** follow the per-skill
`VENDORED.md` convention: provenance (upstream source path and a content hash
per skill) is recorded once in the repo-root `skills-lock.json`, which was the
manifest `npx skills` used to install them into individual repos before this
set was promoted to the base harness. Do not hand-edit these skills — refresh
the whole set at once and update the hashes.

Both harnesses get this set without symlinks: pi reads `~/.agents/skills/`
natively, and Claude Code reads the `mattpocock-skills@claude-plugins-official`
plugin (enabled in `editable-settings.json` for Claude). The plugin currently
ships 35 of the 37 — it omits `implement-spec` and `retro`, which upstream
files under `skills/in-progress/`.

These were formerly vendored per-repo (`<repo>/.agents/skills/`, with matching
`.pi/skills/` and `.claude/skills/` symlinks). That pattern is gone: pi resolves
project `.agents/skills/` before `~/.agents/skills/` and name collisions are
first-wins, so a repo-local copy silently shadows this one. Keep only one copy.
