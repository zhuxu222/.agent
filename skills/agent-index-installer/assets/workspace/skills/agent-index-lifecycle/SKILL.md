---
name: agent-index-lifecycle
description: Orchestrate project index lifecycle across enabled providers. Use for one-command build, refresh, validate, repair, or status of all configured index providers in .agent-index/agent-index.yaml after workspace discovery and manifest setup are complete.
---

# Agent Index Lifecycle

Use this skill to coordinate enabled providers through the project-local Python CLI.

## Command

```text
.agent-index/bin/agent-index lifecycle validate
```

On Windows, use `.agent-index\bin\agent-index.cmd lifecycle validate`.

Supported actions:

- `build`: create provider indexes.
- `refresh`: incremental update/sync provider indexes.
- `validate`: validate configured provider indexes.
- `repair`: run provider repair.
- `status`: show provider status without repair.

Pass `--project-root <path>` before `lifecycle` when running from outside the project root.

## Workflow

1. Validate `.agent-index/agent-index.yaml` exists.
2. Read enabled providers.
3. Dispatch each provider through `.agent-index/bin/agent-index provider <provider> <action>`.
4. Report provider failures separately.

## Rules

- Do not hard-code provider executables outside the Python CLI.
- Keep provider-specific policy in provider lifecycle skills.
- Use lowercase CLI actions exactly as shown above.
