from __future__ import annotations

from pathlib import Path

from .paths import venv_python


def toml_string(value: str) -> str:
    return '"' + value.replace('\\', '\\\\').replace('"', '\\"') + '"'


def codex_config(project_root: Path) -> str:
    agent = project_root / ".agent-index" / "bin" / "agent-index.py"
    python = venv_python(project_root / ".agent-index" / ".venv")
    return "\n".join([
        "[mcp_servers.gitnexus]",
        f"command = {toml_string(str(python))}",
        f"args = [{toml_string(str(agent))}, \"provider\", \"gitnexus\", \"mcp\"]",
        "",
        "[mcp_servers.codegraph]",
        f"command = {toml_string(str(python))}",
        f"args = [{toml_string(str(agent))}, \"provider\", \"codegraph\", \"mcp\"]",
        "",
    ])


def launcher_py() -> str:
    return '''#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / "tools"))
from agent_index.cli import main

raise SystemExit(main())
'''


def launcher_cmd() -> str:
    return '''@echo off
set "ROOT=%~dp0.."
"%ROOT%\\.venv\\Scripts\\python.exe" "%ROOT%\\bin\\agent-index.py" %*
'''


def launcher_sh() -> str:
    return '''#!/usr/bin/env sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(dirname "$DIR")
exec "$ROOT/.venv/bin/python" "$ROOT/bin/agent-index.py" "$@"
'''


def agent_instructions() -> str:
    return """# Agent Instructions

Use indexed code intelligence before broad grep or guessing.

Project index manifest:

- `.agent-index/agent-index.yaml`

Rules:

- Use project-level skills under `.agents/skills`.
- Use `.agent-index/bin/agent-index` on POSIX or `.agent-index/bin/agent-index.cmd` on Windows for index workspace commands.
- Use `agent-index workspace init` for initial workspace setup.
- Use `agent-index lifecycle <mode>` for build, refresh, validation, repair, and status.
- Use usage skills for daily retrieval and analysis.
- For cleanup of generated project-local index assets, use `agent-index clean`.
- Do not run bare `gitnexus` or bare `npx gitnexus`; use project wrappers through `agent-index provider gitnexus`.
- Do not create repo-local `AGENTS.md`, `CLAUDE.md`, or `.claude/skills/...` from GitNexus.
"""

