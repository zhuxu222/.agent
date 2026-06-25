---
name: agent-index-workspace
description: Maintain the current project's index workspace. Use for discovering child git repositories, updating the repos section of .agent-index/agent-index.yaml, validating manifest structure, checking wrapper paths, or preparing repo lists for index lifecycle skills.
---

# Agent Index Workspace

Use this skill for project-level workspace facts. It does not build provider indexes.

## Commands

Discover configured git repos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\discover-repos.ps1
```

Update the manifest `repos:` section from configured git repos:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\update-manifest-repos.ps1
```

Initialize the workspace in the required serial order:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\initialize-workspace.ps1
```

Validate manifest and configured paths:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\validate-manifest.ps1
```

Ensure child repos hide local index directories from `git status`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\ensure-repo-excludes.ps1
```

Clean repo-local index artifacts with a project MCP guard:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\clean-project-index.ps1
```

If project MCP processes are running and cleanup is intentional:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\clean-project-index.ps1 -StopProjectMcp
```

Pass `-ProjectRoot <path>` when running from outside the project root.

## Rules

- Treat `.agent-index/agent-index.yaml` as the project fact source.
- Discover repos from `workspace.repo_roots` when configured. If no workspace configuration exists, preserve the legacy behavior: direct child directories with `.git`.
- Recursive discovery is controlled by `workspace.discovery.recursive` / `workspace.recursive` and `workspace.discovery.max_depth` / `workspace.max_depth`.
- Stop descending once a `.git` file or directory is found, so a nested submodule is not indexed twice when its parent repo is selected.
- For setup, prefer `initialize-workspace.ps1`; do not run manifest update and exclude maintenance in parallel.
- Maintain child repo `.git/info/exclude` entries for local index directories such as `.codegraph/`, `.gitnexus/`, and `.understand-anything/`.
- `clean-project-index.ps1` removes index artifacts only; it does not remove installed `.agents`, `.codex`, `AGENTS.md`, or the manifest.
- If cleanup stops project MCP processes, restart the Codex session before MCP tool verification.
- Do not build CodeGraph or GitNexus indexes here; route that to `agent-index-lifecycle`.
- Keep generated repo names stable from the full project-relative repo path: `<project>-<repo-path-normalized>`.

Example workspace layout:

```yaml
workspace:
  repo_roots:
    - repos
  recursive: true
  max_depth: 8
```
