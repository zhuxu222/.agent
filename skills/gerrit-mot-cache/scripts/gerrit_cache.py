#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import unquote, urlsplit


COMMANDS = {
    "cache-path",
    "update-cache",
    "clone",
    "fetch",
    "pull",
    "validate",
    "repair",
    "push-review",
}


class GerritCacheError(RuntimeError):
    pass


@dataclass(frozen=True)
class Config:
    cache_root: Path
    gerrit_host: str
    main_branch: str
    no_fsck: bool


def default_cache_root() -> Path:
    if os.name == "nt":
        return Path(r"D:\common\solution\lenovo\gerrit\cache\gerrit.mot.com")
    return Path("/data/solution/lenovo/gerrit/cache/gerrit.mot.com")


def host_matches(host: str, expected: str) -> bool:
    host = host.lower().rstrip(".")
    expected = expected.lower().rstrip(".")
    return host == expected or host.endswith("." + expected)


def parse_gerrit_repo_path(url: str, gerrit_host: str) -> str:
    trimmed = url.strip()
    if not trimmed:
        raise GerritCacheError("Missing Gerrit URL.")

    repo_path: str | None = None
    scp_match = re.match(r"^[^@/\s]+@(?P<host>[^:\s]+):(?P<path>.+)$", trimmed)
    if scp_match and host_matches(scp_match.group("host"), gerrit_host):
        repo_path = scp_match.group("path")
    else:
        parsed = urlsplit(trimmed)
        if parsed.scheme not in {"http", "https", "ssh"}:
            raise GerritCacheError(f"Unsupported Gerrit URL format: {url}")
        if not parsed.hostname or not host_matches(parsed.hostname, gerrit_host):
            raise GerritCacheError(f"URL is not a supported Gerrit MOT repository: {url}")
        repo_path = parsed.path[1:] if parsed.path.startswith("/") else parsed.path

    decoded = unquote(repo_path).rstrip("/")
    if decoded.startswith("/"):
        raise GerritCacheError(f"Repository path is absolute after decoding: {url}")
    if decoded.lower().endswith(".git"):
        decoded = decoded[:-4]
    if not decoded:
        raise GerritCacheError(f"Could not derive repository path from URL: {url}")

    segments = decoded.split("/")
    safe_segments: list[str] = []
    for segment in segments:
        if "\x00" in segment:
            raise GerritCacheError(f"Repository path contains a NUL byte: {url}")
        if not segment or segment in {".", ".."}:
            raise GerritCacheError(f"Repository path contains an unsafe segment: {url}")
        if "\\" in segment:
            raise GerritCacheError(f"Repository path contains a backslash: {url}")
        if re.match(r"^[A-Za-z]:", segment):
            raise GerritCacheError(f"Repository path contains a Windows drive segment: {url}")
        if ":" in segment:
            raise GerritCacheError(f"Repository path contains an unsupported ':' segment: {url}")
        safe_segments.append(segment)

    return "/".join(safe_segments)


def ensure_cache_root(root: Path) -> Path:
    root = root.expanduser()
    root.mkdir(parents=True, exist_ok=True)
    resolved = root.resolve(strict=False)
    if not resolved.is_dir():
        raise GerritCacheError(f"Cache root is not a directory: {resolved}")
    if not os.access(resolved, os.W_OK):
        raise GerritCacheError(f"Cache root is not writable: {resolved}")
    return resolved


def ensure_under_root(path: Path, root: Path, label: str) -> Path:
    resolved = path.resolve(strict=False)
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise GerritCacheError(f"Refusing {label} outside cache root: {resolved}") from exc
    return resolved


def cache_path_for_url(config: Config, url: str) -> Path:
    root = ensure_cache_root(config.cache_root)
    repo_path = parse_gerrit_repo_path(url, config.gerrit_host)
    parts = repo_path.split("/")
    base = root.joinpath(*parts)
    cache_path = base.parent / f"{base.name}.git"
    return ensure_under_root(cache_path, root, "cache path")


def git_cmd(args: list[str | os.PathLike[str]], *, input_text: str | None = None) -> None:
    cmd = ["git", *[os.fspath(arg) for arg in args]]
    print("$ " + " ".join(cmd))
    completed = subprocess.run(cmd, input=input_text, text=True)
    if completed.returncode != 0:
        raise GerritCacheError(f"git failed with exit code {completed.returncode}: {' '.join(cmd)}")


def git_output(args: list[str | os.PathLike[str]]) -> str | None:
    cmd = ["git", *[os.fspath(arg) for arg in args]]
    completed = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    if completed.returncode != 0:
        return None
    return completed.stdout.strip()


def get_master_commit(config: Config, cache_path: Path) -> str | None:
    return git_output(["-C", cache_path, "rev-parse", "--verify", f"refs/heads/{config.main_branch}"])


def test_ancestor(repo_path: Path, old_commit: str, new_commit: str) -> bool:
    if old_commit == new_commit:
        return True
    completed = subprocess.run(
        ["git", "-C", os.fspath(repo_path), "merge-base", "--is-ancestor", old_commit, new_commit],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return completed.returncode == 0


def remove_partial_cache(config: Config, cache_path: Path) -> None:
    if not cache_path.exists():
        return
    root = ensure_cache_root(config.cache_root)
    resolved = ensure_under_root(cache_path, root, "partial cache removal")
    if resolved == root:
        raise GerritCacheError(f"Refusing to remove cache root: {resolved}")
    if resolved.is_dir():
        shutil.rmtree(resolved)
    else:
        resolved.unlink()


def remove_partial_worktree(worktree_path: Path) -> None:
    if not worktree_path.exists():
        return
    resolved = worktree_path.resolve(strict=False)
    if resolved == Path(resolved.anchor):
        raise GerritCacheError(f"Refusing to remove partial worktree at filesystem root: {resolved}")
    if not (resolved / ".git").exists():
        raise GerritCacheError(f"Refusing to remove partial worktree without .git marker: {resolved}")
    shutil.rmtree(resolved)


def lock_path(config: Config, cache_path: Path) -> Path:
    root = ensure_cache_root(config.cache_root)
    lock_root = root / ".locks"
    lock_root.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha1(os.fspath(cache_path).encode("utf-8")).hexdigest()
    return lock_root / f"{digest}.lock"


class CacheLock:
    def __init__(self, config: Config, cache_path: Path) -> None:
        self.path = lock_path(config, cache_path)

    def __enter__(self) -> CacheLock:
        for _ in range(120):
            try:
                self.path.mkdir()
                return self
            except FileExistsError:
                time.sleep(0.5)
        raise GerritCacheError(f"Timed out waiting for cache lock: {self.path}")

    def __exit__(self, _exc_type, _exc, _tb) -> None:
        try:
            self.path.rmdir()
        except FileNotFoundError:
            pass


def set_master_only_cache_config(config: Config, cache_path: Path, url: str) -> None:
    git_cmd(["-C", cache_path, "config", "--replace-all", "remote.origin.url", url])
    git_cmd([
        "-C",
        cache_path,
        "config",
        "--replace-all",
        "remote.origin.fetch",
        f"refs/heads/{config.main_branch}:refs/heads/{config.main_branch}",
    ])
    git_cmd(["-C", cache_path, "config", "--replace-all", "remote.origin.tagOpt", "--no-tags"])
    subprocess.run(["git", "-C", os.fspath(cache_path), "config", "--unset-all", "remote.origin.mirror"], stderr=subprocess.DEVNULL)
    git_cmd(["-C", cache_path, "symbolic-ref", "HEAD", f"refs/heads/{config.main_branch}"])


def remove_non_master_cache_refs(config: Config, cache_path: Path) -> None:
    keep_ref = f"refs/heads/{config.main_branch}"
    refs_output = git_output(["-C", cache_path, "for-each-ref", "--format=%(refname)"])
    if not refs_output:
        return
    delete_refs = [line for line in refs_output.splitlines() if line and line != keep_ref]
    if not delete_refs:
        return
    print(f"Removing non-master cache refs: {len(delete_refs)}")
    git_cmd(["-C", cache_path, "update-ref", "--stdin"], input_text="".join(f"delete {ref}\n" for ref in delete_refs))


def update_gerrit_cache(config: Config, url: str) -> Path:
    cache_path = cache_path_for_url(config, url)
    cache_path.parent.mkdir(parents=True, exist_ok=True)

    with CacheLock(config, cache_path):
        if not cache_path.exists():
            try:
                git_cmd([
                    "clone",
                    "--bare",
                    "--single-branch",
                    "--branch",
                    config.main_branch,
                    "--no-tags",
                    "--progress",
                    url,
                    cache_path,
                ])
                set_master_only_cache_config(config, cache_path, url)
                remove_non_master_cache_refs(config, cache_path)
            except Exception:
                remove_partial_cache(config, cache_path)
                raise
            created_master = get_master_commit(config, cache_path)
            if not created_master:
                raise GerritCacheError(f"Cache was created, but refs/heads/{config.main_branch} was not found: {cache_path}")
            print(f"Cache created: {cache_path}")
            return cache_path

        set_master_only_cache_config(config, cache_path, url)
        old_master = get_master_commit(config, cache_path)
        incoming_ref = f"refs/cache/incoming/{config.main_branch}"
        subprocess.run(["git", "-C", os.fspath(cache_path), "update-ref", "-d", incoming_ref], stderr=subprocess.DEVNULL)
        try:
            git_cmd([
                "-C",
                cache_path,
                "fetch",
                "--no-tags",
                "--progress",
                url,
                f"refs/heads/{config.main_branch}:{incoming_ref}",
            ])
            incoming_master = git_output(["-C", cache_path, "rev-parse", "--verify", incoming_ref])
            if not incoming_master:
                raise GerritCacheError(f"Could not fetch origin refs/heads/{config.main_branch} into cache: {cache_path}")
            if old_master and not test_ancestor(cache_path, old_master, incoming_master):
                raise GerritCacheError(
                    f"Gerrit {config.main_branch} non-fast-forward detected before cache update. "
                    f"Old={old_master} New={incoming_master} Cache={cache_path}"
                )

            current_master = get_master_commit(config, cache_path)
            if current_master and current_master != old_master:
                if current_master != incoming_master:
                    raise GerritCacheError(
                        "Cache master changed unexpectedly during fetch. "
                        f"Old={old_master} Current={current_master} Incoming={incoming_master} Cache={cache_path}"
                    )
                print(f"Cache master already updated by fetch: {current_master}")
            elif old_master == incoming_master:
                print(f"Cache master already current: {incoming_master}")
            elif old_master:
                git_cmd(["-C", cache_path, "update-ref", f"refs/heads/{config.main_branch}", incoming_master, old_master])
            else:
                git_cmd(["-C", cache_path, "update-ref", f"refs/heads/{config.main_branch}", incoming_master])
        finally:
            subprocess.run(["git", "-C", os.fspath(cache_path), "update-ref", "-d", incoming_ref], stderr=subprocess.DEVNULL)

        new_master = get_master_commit(config, cache_path)
        if not new_master:
            raise GerritCacheError(f"Cache update removed refs/heads/{config.main_branch}: {cache_path}")
        remove_non_master_cache_refs(config, cache_path)
        print(f"Cache updated: {cache_path}")
        return cache_path


def get_worktree_origin_url(config: Config, worktree_path: Path) -> str:
    origin = git_output(["-C", worktree_path, "config", "--get", "remote.origin.url"])
    if not origin:
        raise GerritCacheError(f"Could not read remote.origin.url from worktree: {worktree_path}")
    parse_gerrit_repo_path(origin, config.gerrit_host)
    return origin


def get_git_dir(worktree_path: Path) -> Path:
    git_dir = git_output(["-C", worktree_path, "rev-parse", "--git-dir"])
    if not git_dir:
        raise GerritCacheError(f"Could not resolve git dir for worktree: {worktree_path}")
    path = Path(git_dir)
    if path.is_absolute():
        return path.resolve(strict=True)
    return (worktree_path / path).resolve(strict=True)


def cache_objects_path(cache_path: Path) -> Path:
    return cache_path / "objects"


def set_alternates(worktree_path: Path, cache_path: Path) -> None:
    git_dir = get_git_dir(worktree_path)
    info_dir = git_dir / "objects" / "info"
    info_dir.mkdir(parents=True, exist_ok=True)
    alternate_file = info_dir / "alternates"
    cache_objects = cache_objects_path(cache_path).as_posix()
    alternate_file.write_text(cache_objects + "\n", encoding="ascii")
    print(f"Alternates set: {alternate_file} -> {cache_objects}")


def set_worktree_longpaths(worktree_path: Path) -> None:
    git_cmd(["-C", worktree_path, "config", "core.longpaths", "true"])


def set_worktree_master_only_fetch(config: Config, worktree_path: Path) -> None:
    git_cmd([
        "-C",
        worktree_path,
        "config",
        "--replace-all",
        "remote.origin.fetch",
        f"+refs/heads/{config.main_branch}:refs/remotes/origin/{config.main_branch}",
    ])
    git_cmd(["-C", worktree_path, "config", "--replace-all", "remote.origin.tagOpt", "--no-tags"])


def update_cache_and_fetch_worktree_master(config: Config, url: str, worktree_path: Path) -> Path:
    for attempt in range(1, 4):
        cache_path = update_gerrit_cache(config, url)
        git_cmd([
            "-C",
            worktree_path,
            "fetch",
            "--prune",
            "--no-tags",
            "--progress",
            "origin",
            f"refs/heads/{config.main_branch}:refs/remotes/origin/{config.main_branch}",
        ])
        cache_master = get_master_commit(config, cache_path)
        worktree_remote_master = git_output([
            "-C",
            worktree_path,
            "rev-parse",
            "--verify",
            f"refs/remotes/origin/{config.main_branch}",
        ])
        if cache_master and worktree_remote_master and cache_master == worktree_remote_master:
            return cache_path
        print(
            f"Cache/worktree {config.main_branch} changed during sync; retrying ({attempt}/3). "
            f"Cache={cache_master} WorktreeOrigin={worktree_remote_master}"
        )
    raise GerritCacheError(f"Could not synchronize cache and worktree origin/{config.main_branch} after 3 attempts: {worktree_path}")


def sync_current_master_branch(config: Config, worktree_path: Path) -> None:
    current_branch = git_output(["-C", worktree_path, "rev-parse", "--abbrev-ref", "HEAD"])
    if current_branch == config.main_branch:
        git_cmd(["-C", worktree_path, "merge", "--ff-only", f"refs/remotes/origin/{config.main_branch}"])
        return
    print(f"Current branch is {current_branch}; fetched origin/{config.main_branch} only. Rebase or merge explicitly.")


def test_alternates(worktree_path: Path, cache_path: Path) -> None:
    git_dir = get_git_dir(worktree_path)
    alternate_file = git_dir / "objects" / "info" / "alternates"
    expected = cache_objects_path(cache_path).as_posix()
    if not alternate_file.exists():
        raise GerritCacheError(f"Missing alternates file: {alternate_file}")
    normalized = alternate_file.read_text(encoding="utf-8").replace("\\", "/")
    if expected not in normalized:
        raise GerritCacheError(f"Alternates does not point at expected cache objects. Expected={expected} File={alternate_file}")
    print(f"Alternates OK: {alternate_file}")


def invoke_validate(config: Config, worktree_path: Path) -> None:
    origin = get_worktree_origin_url(config, worktree_path)
    cache_path = cache_path_for_url(config, origin)
    if not cache_path.exists():
        raise GerritCacheError(f"Expected cache path does not exist: {cache_path}")
    test_alternates(worktree_path, cache_path)
    if not config.no_fsck:
        git_cmd(["-C", worktree_path, "fsck", "--connectivity-only", "--no-dangling"])
    print(f"Validation OK: {worktree_path}")


def require(value: str | None, name: str) -> str:
    if not value:
        raise GerritCacheError(f"Missing required argument: {name}")
    return value


def run_command(config: Config, command: str, target: str | None, worktree: str | None) -> None:
    if command == "cache-path":
        print(cache_path_for_url(config, require(target, "gerrit-url")))
        return
    if command == "update-cache":
        print(update_gerrit_cache(config, require(target, "gerrit-url")))
        return
    if command == "clone":
        url = require(target, "gerrit-url")
        worktree_path = Path(require(worktree, "worktree"))
        cache_path = update_gerrit_cache(config, url)
        if worktree_path.exists():
            raise GerritCacheError(f"Worktree path already exists: {worktree_path}")
        try:
            git_cmd([
                "-c",
                "core.longpaths=true",
                "clone",
                "--reference-if-able",
                cache_path,
                "--single-branch",
                "--branch",
                config.main_branch,
                "--no-tags",
                "--progress",
                url,
                worktree_path,
            ])
        except Exception:
            remove_partial_worktree(worktree_path)
            raise
        set_worktree_longpaths(worktree_path)
        set_worktree_master_only_fetch(config, worktree_path)
        cache_path = update_cache_and_fetch_worktree_master(config, url, worktree_path)
        sync_current_master_branch(config, worktree_path)
        test_alternates(worktree_path, cache_path)
        print(f"Clone OK: {worktree_path}")
        return

    if command == "fetch":
        worktree_path = Path(require(target, "worktree"))
        origin = get_worktree_origin_url(config, worktree_path)
        set_worktree_longpaths(worktree_path)
        set_worktree_master_only_fetch(config, worktree_path)
        update_cache_and_fetch_worktree_master(config, origin, worktree_path)
        return
    if command == "pull":
        worktree_path = Path(require(target, "worktree"))
        origin = get_worktree_origin_url(config, worktree_path)
        set_worktree_longpaths(worktree_path)
        set_worktree_master_only_fetch(config, worktree_path)
        update_cache_and_fetch_worktree_master(config, origin, worktree_path)
        sync_current_master_branch(config, worktree_path)
        return
    if command == "validate":
        invoke_validate(config, Path(require(target, "worktree")))
        return
    if command == "repair":
        worktree_path = Path(require(target, "worktree"))
        origin = get_worktree_origin_url(config, worktree_path)
        cache_path = update_gerrit_cache(config, origin)
        set_worktree_longpaths(worktree_path)
        set_worktree_master_only_fetch(config, worktree_path)
        set_alternates(worktree_path, cache_path)
        invoke_validate(config, worktree_path)
        return
    if command == "push-review":
        worktree_path = Path(require(target, "worktree"))
        get_worktree_origin_url(config, worktree_path)
        set_worktree_longpaths(worktree_path)
        git_cmd(["-C", worktree_path, "push", "origin", f"HEAD:refs/for/{config.main_branch}"])
        return
    raise GerritCacheError(f"Unsupported command: {command}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Cross-platform Gerrit MOT master-only cache helper")
    parser.add_argument("--cache-root", default=None, help="Cache root. Defaults to GERRIT_MOT_CACHE_ROOT or the platform default.")
    parser.add_argument("--gerrit-host", default="gerrit.mot.com", help="Allowed Gerrit host suffix.")
    parser.add_argument("--main-branch", default="master", help="Main branch to cache and fetch.")
    parser.add_argument("--no-fsck", action="store_true", help="Skip git fsck during validate/repair.")
    parser.add_argument("command", choices=sorted(COMMANDS))
    parser.add_argument("target", nargs="?")
    parser.add_argument("worktree", nargs="?")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    root = Path(args.cache_root or os.environ.get("GERRIT_MOT_CACHE_ROOT") or default_cache_root())
    config = Config(cache_root=root, gerrit_host=args.gerrit_host, main_branch=args.main_branch, no_fsck=args.no_fsck)
    try:
        run_command(config, args.command, args.target, args.worktree)
        return 0
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"gerrit-cache: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
