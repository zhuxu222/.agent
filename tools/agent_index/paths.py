from __future__ import annotations

import os
import re
from pathlib import Path


def stable_name(value: str) -> str:
    name = re.sub(r"[^a-z0-9]+", "-", value.lower())
    return name.strip("-") or "project"


def to_posix(path: Path | str) -> str:
    return Path(path).as_posix()


def relative_to_root(root: Path, target: Path) -> str:
    root = root.resolve()
    target = target.resolve()
    if target == root:
        return "."
    return target.relative_to(root).as_posix()


def is_under(child: Path, parent: Path) -> bool:
    child = child.resolve()
    parent = parent.resolve()
    return child == parent or parent in child.parents


def venv_python(venv: Path) -> Path:
    if os.name == "nt":
        return venv / "Scripts" / "python.exe"
    return venv / "bin" / "python"
