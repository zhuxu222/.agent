---
name: agent-index-installer
description: Install or upgrade project-level indexing skills and tool wrappers. Use from the official user skill directory to copy agent index skills into a project's .agents/skills, install .agent-index/bin wrappers, create minimal manifest/config/templates, or upgrade those installed project assets. Does not discover repos, build indexes, refresh indexes, or validate index freshness.
---

# Agent Index Installer

Use this user-level skill only to install or upgrade project-level indexing capabilities.

## Commands

Install into the current project:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\zhuxu\.agents\skills\agent-index-installer\scripts\install-project-index.ps1
```

Upgrade project skills and wrappers:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\zhuxu\.agents\skills\agent-index-installer\scripts\upgrade-project-index.ps1
```

Pass `-ProjectRoot <path>` when running from outside the project root.

## Default Workspace Layout

New installs default to a centralized repo root:

```yaml
workspace:
  repo_roots:
    - repos
  discovery:
    recursive: true
    max_depth: 8
```

Project-level workspace initialization discovers git repos under configured roots, supports multi-level subdirectories, and stops descending once a `.git` file or directory is found.
## Scope

This installer may:

- copy project skills to `.agents/skills`
- copy provider wrappers to `.agent-index/bin`
- create `.agent-index/agent-index.yaml` if missing
- create `.codex/config.toml` if missing
- create or update a minimal `AGENTS.md` indexing section

This installer must not:

- discover repos
- update the manifest `repos:` section from the filesystem
- build CodeGraph or GitNexus indexes
- refresh indexes
- validate index freshness
- run GitNexus analyze

After installation, use project-level skills:

- `agent-index-workspace` for workspace initialization, repo discovery, cleanup of index artifacts, and manifest maintenance
- `agent-index-lifecycle` for build, refresh, validate, repair, and status
- provider usage skills for daily retrieval

Recommended first project command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\.agents\skills\agent-index-workspace\scripts\initialize-workspace.ps1
```
