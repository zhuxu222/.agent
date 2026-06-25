---
name: agent-index-lifecycle
description: Orchestrate project index lifecycle across enabled providers. Use for one-command build, refresh, validate, repair, or status of all configured index providers in .agent-index/agent-index.yaml after workspace discovery and manifest setup are complete.
---

# Agent Index Lifecycle

Use this skill to coordinate enabled providers. Provider internals stay in provider lifecycle skills.

## Command

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-lifecycle\scripts\invoke-agent-index-lifecycle.ps1 -Mode Validate
```

Supported modes:

- `Build`: create or force rebuild provider indexes, then validate.
- `Refresh`: incremental update/sync provider indexes, then validate.
- `Validate`: validate configured provider indexes.
- `Repair`: run provider repair, then validate.
- `Status`: show provider status without repair.

Pass `-ProjectRoot <path>` when running from outside the project root.

## Workflow

1. Validate `.agent-index/agent-index.yaml` exists.
2. Read enabled providers and their `lifecycle_skill`.
3. Ensure child repo `.git/info/exclude` entries hide local index directories.
4. Dispatch to the matching project skill script under `.agents/skills/<lifecycle_skill>/scripts/`.
5. Run `validate.ps1` after `Build`, `Refresh`, or `Repair`.
6. Report provider failures separately.

## Rules

- Do not hard-code provider commands here.
- Require providers to expose `build.ps1`, `refresh.ps1`, `validate.ps1`, `repair.ps1`, and `status.ps1` when supported.
- If a provider script is missing, fail clearly with the expected path.
