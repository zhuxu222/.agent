---
name: python-project-uv
description: Enforce the user-level Python execution policy for Codex with uv-managed workspace environments. Use whenever a task involves Python, uv, py, pip, pytest, virtual environments, package installation, running Python scripts, validating Python-based skills, or any Python command execution. Requires exactly one Python environment at the workspace root `.venv`, forbids system Python, external virtualenvs, Conda envs, and unverified uv environments for project work.
---

# Python Project uv Policy

Use this skill before any Python command.

## Workspace Root

- Resolve `<workspace-root>` before taking Python actions.
- Prefer the current workspace root from the environment context when it is provided.
- Otherwise use the nearest ancestor that contains `.git`, `.agent-index`, `.agents`, `AGENTS.md`, or `.codex`.
- If several nested projects match and the intended root is unclear, ask before creating or modifying an environment.
- The only allowed project environment is `<workspace-root>/.venv`.

## Tool Runtime Exception

- Project code, project tests, and project dependency installs must use `<workspace-root>/.venv`.
- A project-local indexing wrapper may maintain `<workspace-root>/.agent-index/.venv` as its own tool runtime.
- Do not use `<workspace-root>/.agent-index/.venv` to run project code, run project tests, or install project dependencies.
- Apply the same interpreter verification rule to any tool runtime before using it for that tool.

## Hard Rules

- Do not run project code with bare `python`, `py`, `pip`, `pip3`, or `pytest`.
- Do not use system Python, Conda, global virtualenvs, user-site packages, or a `.venv` outside `<workspace-root>` for project work.
- Do not create environments with `python -m venv`, `virtualenv`, Conda, or IDE helpers.
- Do not run project code through `uv run` unless you have verified it uses `<workspace-root>/.venv`; prefer the explicit `.venv` interpreter instead.
- Do not use `uv pip install` without `--python <workspace-root>/.venv/.../python`.
- Do not use `uv pip install --system`, `--target`, or `--prefix` for project dependencies unless the user explicitly asks for packaging/export work rather than a project environment.
- Do not rely on activation state. Always use absolute interpreter paths.
- Stop immediately if `sys.prefix` or `sys.executable` points outside `<workspace-root>/.venv`.

## Create Or Repair The Environment

Create or repair the workspace environment with uv only:

Windows:

```powershell
uv venv <workspace-root>\.venv --python 3.12 --managed-python
```

POSIX:

```sh
uv venv <workspace-root>/.venv --python 3.12 --managed-python
```

If uv-managed Python is unavailable and `python-downloads = "manual"`, install the requested interpreter explicitly with `uv python install <version>`, then create `.venv` again. If the user intentionally wants to use a preinstalled system interpreter as the base interpreter, get explicit confirmation before omitting `--managed-python`.

If `<workspace-root>/.venv` exists but was not created for this workspace, is broken, or points outside the workspace, recreate it with `uv venv <workspace-root>/.venv --clear --managed-python --python <version>` after confirming that deleting the existing environment will not remove user data.

## Interpreter Paths

Use these exact interpreter paths after creating `.venv`:

Windows:

```text
<workspace-root>\.venv\Scripts\python.exe
```

POSIX:

```text
<workspace-root>/.venv/bin/python
```

Install packages only with:

Windows:

```powershell
uv pip install --python <workspace-root>\.venv\Scripts\python.exe <packages>
```

POSIX:

```sh
uv pip install --python <workspace-root>/.venv/bin/python <packages>
```

Run project scripts and tools only with the workspace interpreter:

```text
<workspace-root>/.venv/.../python script.py
<workspace-root>/.venv/.../python -m pytest
<workspace-root>/.venv/.../python -m pip check
```

## Required Verification

Before installing packages, running scripts, or invoking Python tools, verify the interpreter belongs to the workspace `.venv`.

Windows:

```powershell
& <workspace-root>\.venv\Scripts\python.exe -c "import pathlib, sys; p=pathlib.Path(sys.prefix).resolve(); e=pathlib.Path(sys.executable).resolve(); print(e); print(p); assert p == pathlib.Path(r'<workspace-root>/.venv').resolve(); assert str(e).lower().startswith(str(p).lower())"
```

POSIX:

```sh
<workspace-root>/.venv/bin/python -c "import pathlib, sys; p=pathlib.Path(sys.prefix).resolve(); e=pathlib.Path(sys.executable).resolve(); print(e); print(p); assert p == pathlib.Path('<workspace-root>/.venv').resolve(); assert str(e).startswith(str(p))"
```

If verification fails, do not continue. Recreate the workspace `.venv` or ask for direction.

## Cache And Index Policy

- Respect global uv configuration for indexes, Nexus mirrors, `no-cache`, and `python-downloads`.
- Do not require a project `.uv-cache` when a shared Nexus cache is configured.
- If a project-local uv cache is needed, place it at `<workspace-root>/.uv-cache` and do not commit it.
- Add `.venv/` and `.uv-cache/` to the project `.gitignore` when creating them in a git repository and it is safe to edit.

## Python Versions

- Use the version requested by the project files when available, such as `.python-version`, `pyproject.toml`, `requires-python`, docs, or lock files.
- If no project version is specified, choose the smallest supported modern version that fits the task; prefer Python 3.12 for new project work unless dependencies require another version.
- Keep the environment at `<workspace-root>/.venv` even when switching Python versions; recreate it rather than creating another environment.
