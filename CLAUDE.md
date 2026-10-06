# CLAUDE.md

All coding agents share the rules in [AGENTS.md](AGENTS.md). Read it first and follow it; this file does not repeat them.

Then read, as relevant to the task:

- [HANDOFF.md](HANDOFF.md): current state, last verified results, blockers, and next steps.
- [PLAN.md](PLAN.md): the phased delivery plan and the owner decisions each phase needs.
- [docs/PRD.md](docs/PRD.md): product scope and requirements.
- [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md): before any UI change.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): before any technical change. It separates the demonstration prototype from the planned production backend.

## Claude Code cloud sessions

The "Commands" section of AGENTS.md uses Codex cloud paths (`/workspace/...`). In a Claude Code cloud session use these instead:

1. `bash scripts/setup_claude_cloud.sh`, once per fresh VM. It installs the pinned Flutter SDK under `~/.tools` and runs `pub get --enforce-lockfile` and `gen-l10n`.
2. `source scripts/claude_cloud_env.sh` in each shell, then run the Flutter commands from `mobile/` as listed in AGENTS.md.

Do not run `scripts/setup_cloud.sh` or `scripts/cloud_env.sh`; they are Codex-specific. Android builds need `dl.google.com` allowed in the environment's network settings (details in HANDOFF.md).

Work on the branch the session assigns, and never force-push.
