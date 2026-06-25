from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from ..errors import AgentIndexError
from . import codegraph, gitnexus


@dataclass(frozen=True)
class Provider:
    name: str
    handler: Callable[[Path, str, list[str]], None]

    def run(self, project_root: Path, _manifest: dict, action: str, extra: list[str] | None = None) -> int:
        self.handler(project_root, action, extra or [])
        return 0


def _flag(args: list[str], name: str) -> bool:
    return name in args


def _repo_filter(args: list[str]) -> list[str]:
    values: list[str] = []
    i = 0
    while i < len(args):
        if args[i] in {"--repo", "--repos"} and i + 1 < len(args):
            values.extend([p for p in args[i + 1].split(",") if p])
            i += 2
        else:
            i += 1
    return values


def _int_option(args: list[str], name: str, default: int) -> int:
    try:
        idx = args.index(name)
    except ValueError:
        return default
    if idx + 1 >= len(args):
        raise AgentIndexError(f"Missing value for {name}")
    return int(args[idx + 1])


def _codegraph(root: Path, action: str, args: list[str]) -> None:
    if action in {"build", "index"}:
        codegraph.index(root, rebuild=_flag(args, "--force"), repo_filter=_repo_filter(args))
    elif action == "refresh":
        codegraph.index(root, rebuild=False, repo_filter=_repo_filter(args))
    elif action == "repair":
        codegraph.index(root, rebuild=True, repo_filter=_repo_filter(args))
    elif action == "validate":
        codegraph.validate(root)
    elif action == "mcp":
        codegraph.mcp(root)
    elif action == "raw":
        codegraph.run_codegraph(root, args)
    else:
        raise AgentIndexError(f"Unsupported CodeGraph action: {action}")


def _gitnexus(root: Path, action: str, args: list[str]) -> None:
    if action in {"build", "index"}:
        gitnexus.index(
            root,
            force=_flag(args, "--force"),
            repo_filter=_repo_filter(args),
            worker_timeout=_int_option(args, "--worker-timeout", 120),
        )
    elif action == "refresh":
        gitnexus.index(root, force=False, repo_filter=_repo_filter(args))
    elif action == "repair":
        gitnexus.repair(root)
    elif action in {"validate", "status"}:
        gitnexus.status(root)
    elif action == "mcp":
        gitnexus.mcp(root)
    elif action == "clean-injections":
        gitnexus.clean_repo_injections(root, dry_run=_flag(args, "--dry-run"))
    elif action == "raw":
        gitnexus.run_gitnexus(root, args)
    else:
        raise AgentIndexError(f"Unsupported GitNexus action: {action}")


def get_provider(name: str) -> Provider:
    if name == "codegraph":
        return Provider(name=name, handler=_codegraph)
    if name == "gitnexus":
        return Provider(name=name, handler=_gitnexus)
    raise AgentIndexError(f"Unknown provider: {name}")
