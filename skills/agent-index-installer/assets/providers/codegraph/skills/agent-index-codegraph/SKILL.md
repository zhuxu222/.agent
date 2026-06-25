---
name: agent-index-codegraph
description: Lifecycle provider for CodeGraph indexes in the current project. Use for building, refreshing, validating, repairing, or checking repo-level .codegraph indexes through .agent-index/bin/codegraph.ps1. Do not use for daily symbol lookup when agent-codegraph-usage matches.
---

# Agent Index CodeGraph

Use this provider lifecycle skill for CodeGraph index maintenance.

## Provider Interface

```powershell
.\.agents\skills\agent-index-codegraph\scripts\build.ps1
.\.agents\skills\agent-index-codegraph\scripts\refresh.ps1
.\.agents\skills\agent-index-codegraph\scripts\validate.ps1
.\.agents\skills\agent-index-codegraph\scripts\repair.ps1
.\.agents\skills\agent-index-codegraph\scripts\status.ps1
```

Pass `-ProjectRoot <path>` when running from outside the project root.

## Policy

- Keep CodeGraph indexes repo-level.
- Do not create a parent `.codegraph/` unless the user explicitly asks for a cross-repo CodeGraph index.
- Treat missing repo `.codegraph/` directories as blank state and initialize them during build/refresh.
- Use `.agent-index/bin/codegraph.ps1`.
- Daily code lookup belongs in `agent-codegraph-usage`.
