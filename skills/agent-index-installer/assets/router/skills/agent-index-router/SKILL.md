---
name: agent-index-router
description: Entry router for project-level indexed retrieval. Use when Codex needs to decide between workspace discovery, lifecycle build/refresh/validate/repair, CodeGraph usage, GitNexus usage, or future index providers based on .agent-index/agent-index.yaml.
---

# Agent Index Router

Use this skill as the light project-level entry point. It routes work; it does not implement provider-specific commands.

## Workflow

1. Read `.agent-index/agent-index.yaml`.
2. Classify the task:
   - repo discovery, manifest update, manifest validation -> `agent-index-workspace`
   - build, refresh, validate, repair, status for all providers -> `agent-index-lifecycle`
   - concrete repo-local code context -> provider usage skill, normally `agent-codegraph-usage`
   - architecture, process, impact, API, cross-repo analysis -> provider usage skill, normally `agent-gitnexus-usage`
3. If the manifest is missing, ask the user to run the user-level `agent-index-installer` first.
4. If a provider is missing, report the manifest gap instead of guessing commands.

## Rules

- Prefer indexed retrieval before broad grep or guessing.
- Use the project wrapper `.agent-index/bin/agent-index` or `.agent-index\bin\agent-index.cmd`; do not use bare `gitnexus` or bare `npx gitnexus`.
- Keep provider-specific setup in provider lifecycle skills.
- Keep daily code/architecture retrieval in provider usage skills.
- Do not create repo-local `AGENTS.md`, `CLAUDE.md`, or `.claude/skills/...` from GitNexus.

