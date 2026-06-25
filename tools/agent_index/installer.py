from __future__ import annotations

import os
import shutil
from pathlib import Path

from . import manifest
from .errors import AgentIndexError
from .paths import venv_python
from .process import run, which
from .templates import agent_instructions, codex_config, launcher_cmd, launcher_py, launcher_sh


def source_root() -> Path:
    env_root = os.environ.get("AGENT_INDEX_SOURCE_ROOT")
    candidates = [Path(env_root).resolve()] if env_root else []
    here = Path(__file__).resolve()
    candidates.extend(here.parents)
    for candidate in candidates:
        assets = candidate / "skills" / "agent-index-installer" / "assets"
        package = candidate / "tools" / "agent_index"
        if assets.exists() and package.exists():
            return candidate
    raise AgentIndexError("Cannot locate agent-index source root. Set AGENT_INDEX_SOURCE_ROOT to the .agents checkout.")


def copy_children(src: Path, dst: Path, force: bool) -> None:
    if not src.exists():
        return
    dst.mkdir(parents=True, exist_ok=True)
    for item in src.iterdir():
        target = dst / item.name
        if item.is_dir():
            if target.exists() and force:
                shutil.rmtree(target)
            if not target.exists():
                shutil.copytree(item, target)
        else:
            if force or not target.exists():
                shutil.copy2(item, target)


def write_if_missing(path: Path, text: str) -> None:
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def ensure_tool_venv(root: Path, python_version: str = "3.12", skip_install: bool = False) -> Path:
    venv = root / ".agent-index" / ".venv"
    python = venv_python(venv)
    uv_cache = root / ".agent-index" / ".uv-cache"
    uv_cache.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["UV_CACHE_DIR"] = str(uv_cache)
    uv = which("uv")
    if not python.exists():
        run([uv, "venv", str(venv), "--python", python_version], cwd=root, env=env)
    if not skip_install:
        run([uv, "pip", "install", "--python", str(python), "PyYAML", "psutil"], cwd=root, env=env)
    if not python.exists():
        raise AgentIndexError(f"uv did not create expected Python executable: {python}")
    return python


def ensure_project_venv(project_root: Path, python_spec: str = "3.12", install_deps: bool = True) -> int:
    ensure_tool_venv(project_root.resolve(), python_version=python_spec, skip_install=not install_deps)
    return 0


def install(project_root: Path, force: bool = False, skip_venv: bool = False, python_version: str = "3.12") -> int:
    root = project_root.resolve()
    src = source_root()
    assets = src / "skills" / "agent-index-installer" / "assets"

    project_skills = root / ".agents" / "skills"
    agent_index = root / ".agent-index"
    bin_dir = agent_index / "bin"
    tools_dir = agent_index / "tools"
    templates_dir = agent_index / "templates"
    gitnexus_home = agent_index / "gitnexus-home"
    for directory in (project_skills, bin_dir, tools_dir, templates_dir, gitnexus_home):
        directory.mkdir(parents=True, exist_ok=True)

    copy_children(assets / "router" / "skills", project_skills, force)
    copy_children(assets / "workspace" / "skills", project_skills, force)
    copy_children(assets / "providers" / "codegraph" / "skills", project_skills, force)
    copy_children(assets / "providers" / "gitnexus" / "skills", project_skills, force)
    copy_children(assets / "common", templates_dir, force)
    copy_children(assets / "providers" / "gitnexus" / "templates", templates_dir / "gitnexus", force)

    package_src = src / "tools" / "agent_index"
    package_dst = tools_dir / "agent_index"
    if package_dst.exists() and force:
        shutil.rmtree(package_dst)
    if force or not package_dst.exists():
        shutil.copytree(package_src, package_dst)

    (bin_dir / "agent-index.py").write_text(launcher_py(), encoding="utf-8")
    (bin_dir / "agent-index.cmd").write_text(launcher_cmd(), encoding="utf-8")
    sh = bin_dir / "agent-index"
    sh.write_text(launcher_sh(), encoding="utf-8")
    if os.name != "nt":
        sh.chmod(0o755)

    write_if_missing(agent_index / ".gitignore", "/.venv/\n/.uv-cache/\n/npm-cache/\n/xdg-config/\n/gitnexus-home/*\n!/gitnexus-home/.gitignore\n!/gitnexus-home/groups/\n!/gitnexus-home/groups/*/\n!/gitnexus-home/groups/*/group.yaml\n")
    write_if_missing(gitnexus_home / ".gitignore", "/*\n!.gitignore\n!/groups/\n/groups/*\n!/groups/*/\n!/groups/*/group.yaml\n")

    if not manifest.manifest_path(root).exists():
        manifest.write(root, manifest.default_manifest(root.name))
    if not skip_venv:
        ensure_tool_venv(root, python_version=python_version)
    write_if_missing(root / ".codex" / "config.toml", codex_config(root))
    write_if_missing(root / "AGENTS.md", agent_instructions())
    print(f"Installed project index skills and tools under {root}")
    print("Next: run .agent-index/bin/agent-index workspace init, then .agent-index/bin/agent-index lifecycle build")
    return 0


def upgrade(project_root: Path, skip_venv: bool = False, python_version: str = "3.12") -> int:
    return install(project_root, force=True, skip_venv=skip_venv, python_version=python_version)
