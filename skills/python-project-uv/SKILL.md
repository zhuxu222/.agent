---
name: python-project-uv
description: Enforce the user-level Python execution policy for Codex with uv-managed project environments. Use whenever a task involves Python, uv, py, pip, pytest, virtual environments, package installation, running Python scripts, validating Python-based skills, or any Python command execution. Requires a project-local .venv created or managed by uv and forbids bare system python, py, pip, pip3, or pytest for project work.
---

# Python Project uv Policy

Use this skill before any Python command.

## Rules

- Use a project-local uv-managed virtual environment at `<project-root>/.venv`.
- Do not run bare `python`, `py`, `pip`, `pip3`, or `pytest` for project work.
- Do not create environments with `python -m venv`.
- Create or repair the project environment with `uv venv <project-root>/.venv` or the bundled Python helper.
- Install packages with `uv pip install --python <project-root>/.venv/bin/python ...` on POSIX or `uv pip install --python <project-root>\.venv\Scripts\python.exe ...` on Windows.
- Run Python scripts with the project venv interpreter.
- Run Python tools through module form where possible, for example `<project-root>/.venv/bin/python -m pytest`.
- Use a project-local uv cache at `<project-root>/.uv-cache` when running helper-managed uv commands.
- Do not commit `.venv` or `.uv-cache`; add `.venv/` and `.uv-cache/` to the project `.gitignore` when creating a venv in a git repository and the file is safe to edit.
- If an existing `.venv` was not created through this policy, recreate it with the helper's `--recreate` option before installing packages or running project Python commands.
- If the project root is unclear, use the current workspace root when it has `.git`, `.agent-index`, `.agents`, `AGENTS.md`, or `.codex`; otherwise ask for the intended root.

## Bootstrap

Use uv to run the bundled Python helper without relying on a bare system Python command:

```text
uv run --python 3.12 <agents-root>/skills/python-project-uv/scripts/ensure_python_uv.py --project-root <project-root>
```

Install packages into the project uv environment:

```text
uv run --python 3.12 <agents-root>/skills/python-project-uv/scripts/ensure_python_uv.py --project-root <project-root> --package PyYAML
```

Recreate an existing non-uv or stale `.venv`:

```text
uv run --python 3.12 <agents-root>/skills/python-project-uv/scripts/ensure_python_uv.py --project-root <project-root> --recreate --package PyYAML
```

The helper prints the venv Python path. Use that exact executable for later commands.
