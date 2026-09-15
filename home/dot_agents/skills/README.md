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
