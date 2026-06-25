from __future__ import annotations

import os
from pathlib import Path

from .. import manifest
from ..paths import to_posix


def git_safe_dirs(root: Path) -> list[Path]:
    dirs = [root.resolve()]
    try:
        data = manifest.load(root)
        for repo in manifest.repo_entries(data):
            full = (root / repo["path"]).resolve()
            if (full / ".git").exists():
                dirs.append(full)
    except Exception:
        pass
    return sorted(set(dirs), key=lambda p: str(p))


def project_env(root: Path) -> dict[str, str]:
    env = os.environ.copy()
    xdg = root / ".agent-index" / "xdg-config"
    git_ignore = xdg / "git" / "ignore"
    git_ignore.parent.mkdir(parents=True, exist_ok=True)
    git_ignore.touch(exist_ok=True)
    env["XDG_CONFIG_HOME"] = str(xdg)
    entries: list[tuple[str, str]] = [("safe.directory", to_posix(d)) for d in git_safe_dirs(root)]
    entries.append(("core.excludesFile", to_posix(git_ignore)))
    env["GIT_CONFIG_COUNT"] = str(len(entries))
    for index, (key, value) in enumerate(entries):
        env[f"GIT_CONFIG_KEY_{index}"] = key
        env[f"GIT_CONFIG_VALUE_{index}"] = value
    return env
