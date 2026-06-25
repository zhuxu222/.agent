from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path


def venv_python(venv: Path) -> Path:
    if os.name == "nt":
        return venv / "Scripts" / "python.exe"
    return venv / "bin" / "python"


def run(cmd: list[str], cwd: Path, env: dict[str, str]) -> None:
    print("+ " + " ".join(cmd))
    completed = subprocess.run(cmd, cwd=str(cwd), env=env)
    if completed.returncode != 0:
        raise SystemExit(completed.returncode)


def update_gitignore(root: Path) -> None:
    if not (root / ".git").exists():
        return
    gitignore = root / ".gitignore"
    lines = gitignore.read_text(encoding="utf-8").splitlines() if gitignore.exists() else []
    changed = False
    for item in [".venv/", ".uv-cache/"]:
        if item not in lines:
            lines.append(item)
            changed = True
    if changed:
        gitignore.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Create or repair a uv-managed project .venv")
    parser.add_argument("--project-root", default=".")
    parser.add_argument("--python", default=None, help="Python version/spec passed to uv")
    parser.add_argument("--recreate", action="store_true")
    parser.add_argument("--package", action="append", default=[], help="Package to install; may be repeated")
    parser.add_argument("--packages", nargs="*", default=[], help="Packages to install")
    parser.add_argument("--no-gitignore", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    uv = shutil.which("uv")
    if not uv:
        print("uv is required by the user-level Python policy, but uv was not found on PATH.", file=sys.stderr)
        return 1

    root = Path(args.project_root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    venv = root / ".venv"
    python = venv_python(venv)
    uv_cache = root / ".uv-cache"
    uv_cache.mkdir(parents=True, exist_ok=True)

    env = os.environ.copy()
    env["UV_CACHE_DIR"] = str(uv_cache)

    if args.recreate or not python.exists():
        cmd = [uv, "venv"]
        if args.recreate:
            cmd.append("--clear")
        if args.python:
            cmd.extend(["--python", args.python])
        cmd.append(str(venv))
        run(cmd, cwd=root, env=env)

    if not python.exists():
        print(f"uv did not create the expected Python executable: {python}", file=sys.stderr)
        return 1

    packages = [*args.package, *args.packages]
    if packages:
        run([uv, "pip", "install", "--python", str(python), *packages], cwd=root, env=env)

    if not args.no_gitignore:
        update_gitignore(root)

    print(python)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
