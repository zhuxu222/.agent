---
name: agent-index-installer
description: Install or upgrade project-level indexing skills and tool wrappers. Use from the official user skill directory to copy agent index skills into a project's .agents/skills, install .agent-index/bin wrappers, create minimal manifest/config/templates, or upgrade those installed project assets. Does not discover repos, build indexes, refresh indexes, or validate index freshness.
---

# Agent Index Installer

Use this user-level skill only to install or upgrade project-level indexing capabilities.

## Commands

Run the source Python CLI from the `.agents` checkout. Use the uv-managed source environment when it exists.

Install into a project:

```text
<agents-root>/.venv/bin/python <agents-root>/scripts/agent-index.py --project-root <project-root> install
```

Windows equivalent:

```text
<agents-root>\.venv\Scripts\python.exe <agents-root>\scripts\agent-index.py --project-root <project-root> install
```

Upgrade project skills and wrappers:

```text
<agents-root>/.venv/bin/python <agents-root>/scripts/agent-index.py --project-root <project-root> upgrade
```

If the source virtual environment is missing, create it with uv first and install the CLI dependencies:

```text
uv venv <agents-root>/.venv --python 3.12
uv pip install --python <agents-root>/.venv/bin/python PyYAML psutil
```

On Windows, the created interpreter is `<agents-root>\.venv\Scripts\python.exe`.

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
- copy the Python CLI and launchers to `.agent-index/bin` and `.agent-index/tools`
- create `.agent-index/agent-index.yaml` if missing
- create `.codex/config.toml` if missing
- create or update a minimal `AGENTS.md` indexing section
- create a project-local `.agent-index/.venv` with uv unless `--skip-venv` is used

This installer must not:

- discover repos
- update the manifest `repos:` section from the filesystem
- build CodeGraph or GitNexus indexes
- refresh indexes
- validate index freshness
- run GitNexus analyze

After installation, use project-level skills:

- `agent-index-workspace` for workspace initialization, repo discovery, cleanup of generated index assets, and manifest maintenance
- `agent-index-lifecycle` for build, refresh, validate, repair, and status
- provider usage skills for daily retrieval

Recommended first project command:

```text
.agent-index/bin/agent-index workspace init
```

Windows equivalent:

```text
.agent-index\bin\agent-index.cmd workspace init
```
