---
name: agent-index-workspace
description: Maintain the current project's index workspace. Use for discovering child git repositories, updating the repos section of .agent-index/agent-index.yaml, validating manifest structure, checking wrapper paths, or preparing repo lists for index lifecycle skills.
---

# Agent Index Workspace

Use this skill for project-level workspace facts. It does not build provider indexes.

## Commands

Use the project-local Python launcher.

Discover configured git repos:

```text
.agent-index/bin/agent-index workspace discover
```

Update the manifest `repos:` section, update GitNexus group metadata, maintain child repo excludes, and validate:

```text
.agent-index/bin/agent-index workspace init
```

Validate manifest and configured paths:

```text
.agent-index/bin/agent-index workspace validate
```

Clean generated project-local index assets:

```text
.agent-index/bin/agent-index clean
```

Clean generated project-local assets and GitNexus repo-local skill injections:

```text
.agent-index/bin/agent-index clean --include-repo-injections
```

On Windows, use `.agent-index\bin\agent-index.cmd` with the same arguments.

Pass `--project-root <path>` before the subcommand when running from outside the project root.

## Rules

- Treat `.agent-index/agent-index.yaml` as the project fact source.
- Discover repos from `workspace.repo_roots` when configured. If no workspace configuration exists, preserve the legacy behavior: direct child directories with `.git`.
- Recursive discovery is controlled by `workspace.discovery.recursive` / `workspace.recursive` and `workspace.discovery.max_depth` / `workspace.max_depth`.
- Stop descending once a `.git` file or directory is found, so a nested submodule is not indexed twice when its parent repo is selected.
- For setup, prefer `agent-index workspace init`; do not run manifest update and exclude maintenance in parallel.
- Maintain child repo `.git/info/exclude` entries for local index directories such as `.codegraph/`, `.gitnexus/`, and `.understand-anything/`.
- `agent-index clean` removes generated project-local index assets; it does not remove installed `.agents`, `.codex`, `AGENTS.md`, or the manifest.
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
