from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Iterable, Mapping

from .errors import AgentIndexError


def which(*names: str) -> str:
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    raise AgentIndexError(f"Missing required command on PATH: {' or '.join(names)}")


def run(args: Iterable[str | os.PathLike[str]], cwd: Path | None = None, env: Mapping[str, str] | None = None, check: bool = True) -> subprocess.CompletedProcess[bytes]:
    cmd = [os.fspath(arg) for arg in args]
    print("$ " + " ".join(cmd))
    completed = subprocess.run(cmd, cwd=os.fspath(cwd) if cwd else None, env=dict(env) if env else None)
    if check and completed.returncode != 0:
        raise AgentIndexError(f"Command failed with exit code {completed.returncode}: {' '.join(cmd)}")
    return completed


def capture(args: Iterable[str | os.PathLike[str]], cwd: Path | None = None, env: Mapping[str, str] | None = None) -> str:
    cmd = [os.fspath(arg) for arg in args]
    completed = subprocess.run(cmd, cwd=os.fspath(cwd) if cwd else None, env=dict(env) if env else None, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if completed.returncode != 0:
        message = completed.stderr.strip() or completed.stdout.strip()
        raise AgentIndexError(f"Command failed with exit code {completed.returncode}: {' '.join(cmd)}\n{message}")
    return completed.stdout
