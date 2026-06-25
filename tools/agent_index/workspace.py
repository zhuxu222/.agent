from __future__ import annotations

from pathlib import Path
from typing import Any

from . import manifest
from .errors import AgentIndexError
from .paths import relative_to_root, stable_name


def workspace_config(data: dict[str, Any]) -> dict[str, Any]:
    workspace = data.get("workspace") or {}
    discovery = workspace.get("discovery") or {}
    return {
        "repo_roots": workspace.get("repo_roots") or ["."],
        "recursive": bool(discovery.get("recursive", workspace.get("recursive", False))),
        "max_depth": int(discovery.get("max_depth", workspace.get("max_depth", 1))),
        "exclude_dirs": set(workspace.get("exclude_dirs") or [".agent-index", ".agents", ".codex", ".codegraph", ".gitnexus", ".understand-anything", "node_modules"]),
    }


def is_git_repo(path: Path) -> bool:
    return (path / ".git").exists()


def discover(root: Path) -> list[dict[str, str]]:
    data = manifest.load(root)
    config = workspace_config(data)
    project = stable_name(str(data.get("project") or root.name))
    found: list[dict[str, str]] = []

    def add(repo: Path) -> None:
        rel = relative_to_root(root, repo)
        found.append({"path": rel, "name": f"{project}-{stable_name(rel)}", "fullPath": str(repo.resolve())})

    def visit(directory: Path, depth: int) -> None:
        if depth > config["max_depth"]:
            return
        for child in sorted((p for p in directory.iterdir() if p.is_dir()), key=lambda p: str(p)):
            if child.name in config["exclude_dirs"]:
                continue
            if is_git_repo(child):
                add(child)
                continue
            if config["recursive"]:
                visit(child, depth + 1)

    for repo_root in config["repo_roots"]:
        start = Path(repo_root)
        if not start.is_absolute():
            start = root / start
        if not start.exists():
            continue
        start = start.resolve()
        if is_git_repo(start):
            add(start)
        else:
            visit(start, 1)

    dedup = {repo["path"]: repo for repo in found}
    return [dedup[key] for key in sorted(dedup)]


def discover_command(root: Path) -> int:
    repos = discover(root)
    for repo in repos:
        print(f"{repo['path']} -> {repo['name']}")
    print(f"Discovered repos: {len(repos)}")
    return 0


def write_group(root: Path, data: dict[str, Any], repos: list[dict[str, str]]) -> None:
    group = manifest.gitnexus_group(data)
    if not group:
        return
    group_dir = root / ".agent-index" / "gitnexus-home" / "groups" / group
    group_dir.mkdir(parents=True, exist_ok=True)
    lines = ["version: 1", f"name: {group}", "description: ''", "repos:"]
    for repo in repos:
        lines.append(f"  {repo['path']}: {repo['name']}")
    lines.extend([
        "links: []",
        "packages: {}",
        "detect:",
        "  http: true",
        "  grpc: true",
        "  thrift: true",
        "  topics: true",
        "  shared_libs: true",
        "  embedding_fallback: true",
        "  includes: false",
        "  workspace_deps: false",
        "matching:",
        "  bm25_threshold: 0.7",
        "  embedding_threshold: 0.65",
        "  max_candidates_per_step: 3",
        "  exclude_links_paths: []",
        "  exclude_links_param_only_paths: false",
    ])
    (group_dir / "group.yaml").write_text("\n".join(lines) + "\n", encoding="utf-8")


def update_manifest_repos(root: Path) -> None:
    data = manifest.load(root)
    repos = discover(root)
    data["repos"] = [{"path": repo["path"], "name": repo["name"]} for repo in repos]
    manifest.write(root, data)
    write_group(root, data, repos)
    print(f"Updated manifest repos: {len(repos)}")


def git_dir(repo: Path) -> Path:
    git_path = repo / ".git"
    if git_path.is_dir():
        return git_path
    if git_path.is_file():
        for line in git_path.read_text(encoding="utf-8").splitlines():
            if line.startswith("gitdir:"):
                value = line.split(":", 1)[1].strip()
                path = Path(value)
                if not path.is_absolute():
                    path = repo / path
                return path.resolve()
    raise AgentIndexError(f"Cannot resolve git dir for repo: {repo}")


def ensure_repo_excludes(root: Path) -> None:
    data = manifest.load(root)
    for repo in manifest.repo_entries(data):
        repo_path = (root / repo["path"]).resolve()
        if not repo_path.exists():
            raise AgentIndexError(f"Repo path missing: {repo['path']}")
        info = git_dir(repo_path) / "info"
        info.mkdir(parents=True, exist_ok=True)
        exclude = info / "exclude"
        existing = exclude.read_text(encoding="utf-8").splitlines() if exclude.exists() else []
        changed = False
        for pattern in [".codegraph/", ".gitnexus/", ".understand-anything/"]:
            if pattern not in existing:
                existing.append(pattern)
                changed = True
        if changed:
            exclude.write_text("\n".join(existing) + "\n", encoding="utf-8")
            print(f"Updated excludes: {exclude}")


def validate_manifest(root: Path) -> int:
    data = manifest.load(root)
    errors: list[str] = []
    for key in ["version", "project", "providers", "repos", "policies"]:
        if key not in data:
            errors.append(f"Missing top-level section/value: {key}")
    repos = manifest.repo_entries(data)
    if not repos:
        errors.append("No repos configured.")
    for repo in repos:
        full = root / repo["path"]
        if not full.exists():
            errors.append(f"Repo path missing: {repo['path']}")
        elif not is_git_repo(full):
            errors.append(f"Repo path is not a git repo: {repo['path']}")
    for _, provider in manifest.enabled_providers(data):
        for key in ["lifecycle_skill", "usage_skill"]:
            if provider.get(key):
                skill = root / ".agents" / "skills" / str(provider[key]) / "SKILL.md"
                if not skill.exists():
                    errors.append(f"Project skill missing: {provider[key]}")
    if errors:
        for error in errors:
            print(error)
        raise AgentIndexError(f"Manifest validation failed with {len(errors)} error(s).")
    print(f"Manifest OK: {manifest.manifest_path(root)}")
    return 0


def initialize(root: Path) -> int:
    update_manifest_repos(root)
    ensure_repo_excludes(root)
    return validate_manifest(root)
