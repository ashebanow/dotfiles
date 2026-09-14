# ~/.agents/skills — user-level agent skills

Skills every agent on this account should see, regardless of repo. Deployed
by chezmoi from `home/dot_agents/skills/`.

Who reads this directory:

- **pi** scans `~/.agents/skills/` natively — nothing else to wire.
- **Claude Code** does not; it reads `~/.claude/skills/`, so each skill here
  gets a relative symlink there (`home/dot_claude/skills/symlink_<name>`
  → `../../.agents/skills/<name>`). Note `~/.claude` is excluded on headless
  hosts, so Claude Code there sees none of these; pi still does.
- `npx skills add …` (skills.sh) also installs into this directory and tracks
  its own entries in `~/.agents/.skill-lock.json`; chezmoi-managed skills are
  not in that lock and must not be `npx skills`-updated.

Vendored third-party skills carry a `VENDORED.md` with tag and provenance and
a `just` recipe that refreshes them (see the repo justfile); never hand-edit.
