---
name: agent-gitnexus-usage
description: Use GitNexus inside a project that has repo-level .gitnexus indexes and project-local .agent-index/gitnexus-home. Trigger this skill for architecture understanding, execution flows, functional areas, change impact, API route consumers, cross-repo repo-group analysis, PR or diff risk, and cases where Codex needs more than local symbol lookup.
---

# Agent GitNexus Usage

Use GitNexus for architecture, flow, impact, and cross-repo context. This is a high-frequency usage skill; setup, analyze, group sync, and cleanup belong in `agent-index-gitnexus`.

## Routing

Use GitNexus first when the user asks:

- how a feature or subsystem works across files
- what will break if a symbol, module, API route, or shared behavior changes
- which execution processes or functional areas are affected
- how API routes map to consumers
- how multiple repos relate through a project group
- what current git changes affect

Prefer CodeGraph first for precise repo-local source lookup, callers/callees, and call paths.

## Required Context

1. Use GitNexus MCP tools configured for the project-local `GITNEXUS_HOME`.
2. If multiple repos are indexed, pass `repo` explicitly.
3. Use group mode `repo="@<groupName>"` or `repo="@<groupName>/<memberPath>"` for cross-repo analysis.
4. If index data is missing or stale, load `agent-index-gitnexus` and refresh before trusting process, impact, or group data.
5. Do not pass `--skills` unless the user explicitly wants repo-local generated skills.

## Tool Order

- `list_repos` to confirm indexed repos
- `query` for architecture and process discovery
- `context` for one symbol or class in depth
- `impact` before changing shared code
- `detect_changes` before commit or review
- `api_impact`, `route_map`, and `shape_check` before changing API handlers
- `cypher` only when high-level tools cannot answer the structural question

Read the GitNexus schema before custom Cypher.

## Reporting

Report:

- target repo or group used
- index freshness
- high-confidence direct impact separately from indirect impact
- test or validation gaps
- when a conclusion is an inference from graph data rather than direct source reading
