from __future__ import annotations

import os
import shutil
from pathlib import Path

from .. import manifest
from ..errors import AgentIndexError
from ..process import capture, run, which
from .common import project_env


def npx_command() -> str:
    return which("npx.cmd", "npx")


def env(root: Path) -> dict[str, str]:
    result = project_env(root)
    agent_index = root / ".agent-index"
    result["GITNEXUS_HOME"] = str(agent_index / "gitnexus-home")
    result["npm_config_cache"] = str(agent_index / "npm-cache")
    result.setdefault("NODE_NO_WARNINGS", "1")
    Path(result["GITNEXUS_HOME"]).mkdir(parents=True, exist_ok=True)
    Path(result["npm_config_cache"]).mkdir(parents=True, exist_ok=True)
    return result


def run_gitnexus(root: Path, args: list[str], cleanup: bool = True) -> None:
    version = os.environ.get("GITNEXUS_VERSION", "1.6.4")
    raw = list(args)
    if raw and raw[0] == "analyze" and "--skills" not in raw and "--skip-skills" not in raw:
        raw.append("--skip-skills")
    run([npx_command(), "-y", f"gitnexus@{version}", *raw], cwd=root, env=env(root))
    if cleanup:
        clean_repo_injections(root)


def mcp(root: Path) -> None:
    version = os.environ.get("GITNEXUS_VERSION", "1.6.4")
    run([npx_command(), "-y", f"gitnexus@{version}", "mcp"], cwd=root, env=env(root))


def clean_repo_injections(root: Path, dry_run: bool = False) -> None:
    try:
        repos = manifest.repo_entries(manifest.load(root))
    except Exception:
        repos = []
    for repo in repos:
        repo_root = (root / repo["path"]).resolve()
        if not (repo_root / ".git").exists():
            continue
        for relative in [Path(".claude/skills/gitnexus"), Path(".claude/skills/generated")]:
            target = repo_root / relative
            if not target.exists():
                continue
            tracked = capture(["git", "-C", str(repo_root), "ls-files", "--", relative.as_posix()], env=env(root)).strip()
            if tracked:
                print(f"[skip tracked] {target}")
                continue
            if dry_run:
                print(f"[dry-run remove] {target}")
            else:
                if target.is_dir():
                    shutil.rmtree(target)
                else:
                    target.unlink()
                print(f"[removed] {target}")


def index(root: Path, force: bool = False, repo_filter: list[str] | None = None, worker_timeout: int = 120, max_file_size: int | None = None) -> None:
    data = manifest.load(root)
    repos = manifest.repo_entries(data)
    selected = [repo for repo in repos if not repo_filter or repo["path"] in repo_filter or repo["name"] in repo_filter]
    if not selected:
        raise AgentIndexError("No repos selected from manifest.")
    max_file_size = max_file_size or manifest.gitnexus_max_file_size_kb(data)
    for repo in selected:
        full = root / repo["path"]
        if not full.exists():
            raise AgentIndexError(f"Repo path does not exist: {full}")
        args = ["analyze", str(full), "--skip-agents-md", "--name", repo["name"], "--worker-timeout", str(worker_timeout), "--max-file-size", str(max_file_size)]
        if force:
            args.append("--force")
        print(f"GitNexus analyze: {repo['path']} as {repo['name']}")
        run_gitnexus(root, args, cleanup=False)
    group = manifest.gitnexus_group(data)
    if group:
        print(f"GitNexus group sync: {group}")
        run_gitnexus(root, ["group", "sync", group, "--skip-embeddings"], cleanup=False)
    clean_repo_injections(root)


def status(root: Path) -> None:
    print("GitNexus indexed repos:")
    run_gitnexus(root, ["list"], cleanup=False)
    group = manifest.gitnexus_group(manifest.load(root))
    if group:
        print(f"GitNexus group status: {group}")
        run_gitnexus(root, ["group", "status", group], cleanup=False)
    print("GitNexus repo injection cleanup dry run:")
    clean_repo_injections(root, dry_run=True)


def repair(root: Path) -> None:
    clean_repo_injections(root)
    group = manifest.gitnexus_group(manifest.load(root))
    if group:
        run_gitnexus(root, ["group", "sync", group, "--skip-embeddings"], cleanup=False)
    status(root)
