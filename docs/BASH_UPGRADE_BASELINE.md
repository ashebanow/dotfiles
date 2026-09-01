# BASH_UPGRADE — Phase 0 baseline

Snapshot taken before any migration work, for comparison in later phases.

- **Date:** 2026-09-01
- **Machine:** macOS (aarch64-apple-darwin25.6.0)
- **Branch:** `bash-upgrade` from `main` @ `d652dad`
- **Versions:** chezmoi v2.72.0 (nixpkgs) · zsh 5.9.2

## chezmoi diff snapshot

44 lines of **pre-existing drift, all in `.pi/agent/settings.json`** (the pi
agent rewrites its own settings on disk; formatting/version churn, unrelated
to shell config). **Excluded from phase diff comparisons.** No shell-config
drift at baseline — every subsequent phase's `chezmoi diff` should show only
its intended changes plus this same `.pi` noise.

## zsh interactive startup time

`hyperfine -N --warmup 1 -r 6`:

| Command | Mean ± σ | User | System | Range |
|---|---|---|---|---|
| `zsh -i -c exit` | 2.475 s ± 0.100 | 1.281 s | 1.048 s | 2.356–2.628 |
| `zsh -i -l -c exit` | 2.416 s ± 0.119 | 1.239 s | 1.012 s | 2.291–2.572 |

Notes:

- Non-PTY context emits `(eval):1: can't change option: zle` twice — a
  harmless artifact of `zsh -i -c` without a tty, not a config error.
- Login ≈ interactive within noise (macOS `path_helper` replay overhead is
  negligible at this scale).
- ~2.5 s is slow in absolute terms (zinit + secrets cache refresh + tool
  hooks dominate); the shared-layer migration must **not** regress it further.

## What this protects

- §9 acceptance criterion: "zsh startup time not regressed (zinit still
  lazy-loads)"
- Attribution for later `chezmoi diff` comparisons (the `.pi/agent/settings.json`
  noise is pre-existing, not ours)
