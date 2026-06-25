from __future__ import annotations

import shutil
from pathlib import Path

from .manifest import load_manifest, repo_entries
from .providers.gitnexus import clean_repo_injections


def generated_paths(project_root: Path) -> list[Path]:
    return [
        project_root / ".agent-index" / "bin",
        project_root / ".agent-index" / "tools",
        project_root / ".agent-index" / "skills",
        project_root / ".agent-index" / "templates",
        project_root / ".agent-index" / "gitnexus-home",
    ]


def clean(project_root: Path, include_repo_injections: bool = False) -> int:
    for path in generated_paths(project_root):
        if path.exists():
            shutil.rmtree(path)
            print(f"removed {path}")

    if include_repo_injections:
        manifest = load_manifest(project_root)
        if repo_entries(manifest):
            clean_repo_injections(project_root)
    return 0
