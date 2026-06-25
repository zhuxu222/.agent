from __future__ import annotations

from pathlib import Path

from .. import manifest
from ..errors import AgentIndexError
from ..process import run, which
from .common import project_env


def codegraph_command() -> str:
    return which("codegraph.cmd", "codegraph")


def run_codegraph(root: Path, args: list[str]) -> None:
    run([codegraph_command(), *args], cwd=root, env=project_env(root))


def mcp(root: Path) -> None:
    run_codegraph(root, ["serve", "--mcp"])


def index(root: Path, rebuild: bool = False, repo_filter: list[str] | None = None) -> None:
    data = manifest.load(root)
    repos = manifest.repo_entries(data)
    selected = [repo for repo in repos if not repo_filter or repo["path"] in repo_filter or repo["name"] in repo_filter]
    if not selected:
        raise AgentIndexError("No repos selected from manifest.")
    for repo in selected:
        full = root / repo["path"]
        if not full.exists():
            raise AgentIndexError(f"Repo path does not exist: {full}")
        codegraph_dir = full / ".codegraph"
        if not codegraph_dir.exists():
            print(f"CodeGraph init: {repo['path']}")
            run_codegraph(root, ["init", str(full)])
        elif rebuild:
            print(f"CodeGraph rebuild: {repo['path']}")
            run_codegraph(root, ["index", "--force", str(full)])
        else:
            print(f"CodeGraph sync: {repo['path']}")
            run_codegraph(root, ["sync", str(full)])


def validate(root: Path) -> None:
    data = manifest.load(root)
    repos = manifest.repo_entries(data)
    if not repos:
        raise AgentIndexError("No repos configured.")
    for repo in repos:
        full = root / repo["path"]
        if not full.exists():
            raise AgentIndexError(f"Repo path missing: {repo['path']}")
        if not (full / ".codegraph").exists():
            print(f"CodeGraph index missing: {repo['path']}")
    print("CodeGraph validation completed.")
