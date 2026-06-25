---
name: agent-index-gitnexus
description: Lifecycle provider for GitNexus indexes in the current project. Use for analyze, force rebuild, refresh, validate, repair, group sync, project-local GitNexus registry, and cleanup of generated repo-local skill files. Do not use for daily architecture or impact queries when agent-gitnexus-usage matches.
---

# Agent Index GitNexus

Use this provider lifecycle skill for GitNexus index maintenance.

## Provider Interface

```text
.agent-index/bin/agent-index provider gitnexus index
.agent-index/bin/agent-index provider gitnexus status
.agent-index/bin/agent-index provider gitnexus repair
.agent-index/bin/agent-index provider gitnexus clean-injections
.agent-index/bin/agent-index provider gitnexus mcp
```

On Windows, use `.agent-index\bin\agent-index.cmd` with the same arguments.

Pass `--project-root <path>` before `provider` when running from outside the project root.

## Policy

- Keep GitNexus code indexes repo-level.
- Keep GitNexus registry, groups, and contracts project-local under `.agent-index/gitnexus-home`.
- Do not generate repo-local `AGENTS.md`, `CLAUDE.md`, or `.claude/skills/...`.
- Use `.agent-index/bin/agent-index provider gitnexus`; do not use bare `gitnexus` or bare `npx gitnexus`.
- Daily architecture and impact queries belong in `agent-gitnexus-usage`.
