# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the
codebase.

## Before exploring, read these

- **`AGENTS.md`** at the repo root — repo layout, the chezmoi source/target model, install
  scripts, secrets handling, and the platform/template conventions.
- **`CONTEXT.md`** at the repo root — the domain glossary (`headless`, `personal secret`,
  `server secret`, `machine user`, `shared shell layer`). Use this vocabulary in tickets and
  briefs.
- **`docs/`** — upgrade and architecture notes (`BASH_UPGRADE.md`, `BITWARDEN.md`).
- **`docs/adr/`** — read ADRs that touch the area you're about to work in.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't
suggest creating them upfront.

## File structure

Single-context repo: one shared domain model for the whole config — the chezmoi source/target
mapping, platform detection, the `headless` machine class, and the BWS/secretspec secret flow.

```
/
├── AGENTS.md
├── CONTEXT.md                        ← domain glossary
├── home/                             ← chezmoi target root (dot_*, private_*, *.tmpl)
├── lib/install/                      ← manual installers, run by install.sh
├── lib/common/                       ← shared shell helpers sourced by the installers
├── lib/bootstrap/
├── bootstrap.sh · install.sh · install-headless.sh
└── docs/                             ← upgrade + architecture notes
```

## ADRs are created lazily

`docs/adr/` does not exist yet, and shouldn't be created speculatively — an empty directory
can't be committed to git anyway. Create it when the first ADR is needed.

## Flag ADR conflicts

If your output contradicts an existing decision, surface it explicitly rather than silently
overriding.
