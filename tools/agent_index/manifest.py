from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from .paths import stable_name


def manifest_path(root: Path) -> Path:
    return root / ".agent-index" / "agent-index.yaml"


def load(root: Path) -> dict[str, Any]:
    path = manifest_path(root)
    if not path.exists():
        raise FileNotFoundError(f"Missing manifest: {path}")
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    if not isinstance(data, dict):
        raise ValueError(f"Manifest must be a mapping: {path}")
    return data


load_manifest = load


def write(root: Path, data: dict[str, Any]) -> None:
    path = manifest_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    text = yaml.safe_dump(data, sort_keys=False, allow_unicode=False)
    path.write_text(text, encoding="utf-8")


write_manifest = write


def default_manifest(project_name: str) -> dict[str, Any]:
    project = stable_name(project_name)
    return {
        "version": 1,
        "project": project,
        "workspace": {
            "repo_roots": ["repos"],
            "discovery": {"recursive": True, "max_depth": 8},
            "exclude_dirs": [
                ".agent-index",
                ".agents",
                ".codex",
                ".codegraph",
                ".gitnexus",
                ".understand-anything",
                "node_modules",
            ],
        },
        "index_system": {
            "entry_skill": "agent-index-router",
            "workspace_skill": "agent-index-workspace",
            "lifecycle_skill": "agent-index-lifecycle",
        },
        "providers": {
            "codegraph": {
                "enabled": True,
                "lifecycle_skill": "agent-index-codegraph",
                "usage_skill": "agent-codegraph-usage",
                "scope": "code",
                "index_scope": "repo",
                "wrapper": ".agent-index/bin/agent-index.py provider codegraph index",
                "mcp": ".agent-index/bin/agent-index.py provider codegraph mcp",
            },
            "gitnexus": {
                "enabled": True,
                "lifecycle_skill": "agent-index-gitnexus",
                "usage_skill": "agent-gitnexus-usage",
                "scope": "architecture-impact",
                "index_scope": "repo-group",
                "wrapper": ".agent-index/bin/agent-index.py provider gitnexus index",
                "mcp": ".agent-index/bin/agent-index.py provider gitnexus mcp",
                "home": ".agent-index/gitnexus-home",
                "group": project,
                "max_file_size": "256KB",
                "optional_grammars": {"dart": False, "proto": False},
            },
        },
        "repos": [],
        "policies": {
            "prefer_indexed_retrieval": True,
            "no_parent_codegraph": True,
            "no_repo_local_agent_files": True,
            "clean_gitnexus_repo_skills": True,
        },
    }


def repo_entries(data: dict[str, Any]) -> list[dict[str, str]]:
    entries = []
    for item in data.get("repos") or []:
        if isinstance(item, dict) and item.get("path"):
            entries.append({"path": str(item["path"]), "name": str(item.get("name") or item["path"])})
    return entries


def enabled_providers(data: dict[str, Any]) -> list[tuple[str, dict[str, Any]]]:
    result = []
    for name, provider in (data.get("providers") or {}).items():
        if isinstance(provider, dict) and provider.get("enabled", True):
            result.append((str(name), provider))
    return result


def gitnexus_group(data: dict[str, Any]) -> str | None:
    provider = (data.get("providers") or {}).get("gitnexus") or {}
    group = provider.get("group")
    return str(group) if group else None


def gitnexus_max_file_size_kb(data: dict[str, Any], default: int = 256) -> int:
    provider = (data.get("providers") or {}).get("gitnexus") or {}
    value = str(provider.get("max_file_size", default)).strip().lower()
    if value.endswith("kb"):
        return int(value[:-2])
    if value.endswith("k"):
        return int(value[:-1])
    if value.endswith("mb"):
        return int(value[:-2]) * 1024
    if value.endswith("m"):
        return int(value[:-1]) * 1024
    return int(value)
