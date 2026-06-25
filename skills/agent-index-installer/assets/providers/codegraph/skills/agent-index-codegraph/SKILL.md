---
name: agent-index-codegraph
description: Lifecycle provider for CodeGraph indexes in the current project. Use for building, refreshing, validating, repairing, or checking repo-level .codegraph indexes through .agent-index/bin/agent-index. Do not use for daily symbol lookup when agent-codegraph-usage matches.
---

# Agent Index CodeGraph

Use this provider lifecycle skill for CodeGraph index maintenance.

## Provider Interface

```text
.agent-index/bin/agent-index provider codegraph index
.agent-index/bin/agent-index provider codegraph validate
.agent-index/bin/agent-index provider codegraph repair
.agent-index/bin/agent-index provider codegraph mcp
```

On Windows, use `.agent-index\bin\agent-index.cmd` with the same arguments.

Pass `--project-root <path>` before `provider` when running from outside the project root.

## Policy

- Keep CodeGraph indexes repo-level.
- Do not create a parent `.codegraph/` unless the user explicitly asks for a cross-repo CodeGraph index.
- Treat missing repo `.codegraph/` directories as blank state and initialize them during build/refresh.
- Use `.agent-index/bin/agent-index provider codegraph`.
- Daily code lookup belongs in `agent-codegraph-usage`.

