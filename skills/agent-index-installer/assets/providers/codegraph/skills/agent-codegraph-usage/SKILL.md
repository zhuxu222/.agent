---
name: agent-codegraph-usage
description: Use CodeGraph inside a project that has repo-level .codegraph indexes. Trigger this skill for concrete code lookup, symbol discovery, callers/callees, call paths, source snippets, local implementation questions, bug tracing in one repo, or when Codex needs the smallest sufficient code context before reading files or using grep.
---

# Agent CodeGraph Usage

Use CodeGraph as the first hop for precise repo-local code context. This is a high-frequency usage skill; setup and refresh belong in `agent-index-codegraph`.

## Routing

Use CodeGraph first when the user asks:

- where a function, class, route, component, or file is defined
- what calls a symbol or what a symbol calls
- how one symbol reaches another symbol
- how a concrete implementation works inside one repo
- for source snippets or related files before editing

Prefer GitNexus instead for cross-repo impact, architecture, functional areas, API consumers, and process-level risk.

## Required Context

1. Identify the target repo.
2. Pass `projectPath` explicitly when using CodeGraph MCP tools.
3. If the target repo is unknown, use GitNexus or `.agent-index/agent-index.yaml` to identify it first.
4. If CodeGraph reports missing or stale indexes, load `agent-index-codegraph` and refresh before continuing.

## Tool Order

For broad code questions, call `codegraph_context` first. It returns entry points, related symbols, and snippets in one call.

Use narrower tools after that:

- `codegraph_search` for symbol names
- `codegraph_node` for one symbol body
- `codegraph_callers` and `codegraph_callees` for direct relationships
- `codegraph_trace` for a path between two symbols
- `codegraph_impact` before local refactors
- `codegraph_files` for indexed file layout

After CodeGraph returns full source for a file or symbol, treat that source as already read. Re-open files only for exact line verification or stale-file checks.

## Fallback

Use `rg` only when:

- CodeGraph index is missing and lifecycle refresh is not available
- CodeGraph result is ambiguous
- CodeGraph result is stale and cannot be refreshed immediately
- the question depends on raw text not captured by the index

When falling back, search for names or paths surfaced by CodeGraph instead of scanning the whole repo.
