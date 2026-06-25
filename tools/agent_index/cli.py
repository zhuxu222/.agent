from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from . import clean as clean_mod
from . import installer, lifecycle, workspace
from .manifest import load_manifest
from .providers import get_provider
from .validation import validate_skills


def _project_root(value: str | None) -> Path:
    return Path(value).resolve() if value else Path.cwd().resolve()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="agent-index", description="Cross-platform agent index manager")
    parser.add_argument("--project-root", default=None, help="Workspace/project root. Defaults to current directory.")
    parser.add_argument("--version", action="version", version=f"agent-index {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("install", help="Install project-local indexing assets")
    p.add_argument("--force", action="store_true")
    p.add_argument("--skip-venv", action="store_true", help="Do not create .agent-index/.venv")
    p.add_argument("--python", dest="python_spec", default="3.12", help="Python version/spec passed to uv")
    p.set_defaults(func=lambda args: installer.install(_project_root(args.project_root), force=args.force, skip_venv=args.skip_venv, python_version=args.python_spec))

    p = sub.add_parser("upgrade", help="Upgrade project-local indexing assets")
    p.add_argument("--skip-venv", action="store_true")
    p.add_argument("--python", dest="python_spec", default="3.12")
    p.set_defaults(func=lambda args: installer.upgrade(_project_root(args.project_root), skip_venv=args.skip_venv, python_version=args.python_spec))

    p = sub.add_parser("ensure-venv", help="Create or repair .agent-index/.venv")
    p.add_argument("--skip-install", action="store_true", help="Create venv without installing Python dependencies")
    p.add_argument("--python", dest="python_spec", default="3.12")
    p.set_defaults(func=lambda args: installer.ensure_project_venv(_project_root(args.project_root), python_spec=args.python_spec, install_deps=not args.skip_install))

    p = sub.add_parser("workspace", help="Maintain .agent-index workspace metadata")
    wsub = p.add_subparsers(dest="workspace_command", required=True)
    q = wsub.add_parser("init", help="Discover repos and write manifest/group metadata")
    q.set_defaults(func=lambda args: workspace.initialize(_project_root(args.project_root)))
    q = wsub.add_parser("discover", help="Discover child git repositories")
    q.set_defaults(func=lambda args: workspace.discover_command(_project_root(args.project_root)))
    q = wsub.add_parser("validate", help="Validate manifest and wrapper paths")
    q.set_defaults(func=lambda args: workspace.validate_manifest(_project_root(args.project_root)))

    p = sub.add_parser("lifecycle", help="Run lifecycle action for all enabled providers")
    p.add_argument("action", choices=["build", "refresh", "validate", "repair", "status"])
    p.add_argument("provider_args", nargs=argparse.REMAINDER)
    p.set_defaults(func=lambda args: lifecycle.run(_project_root(args.project_root), args.action, args.provider_args))

    p = sub.add_parser("provider", help="Run a provider command")
    p.add_argument("provider", choices=["codegraph", "gitnexus"])
    p.add_argument("action", help="Provider action such as index, mcp, validate, status, repair, or clean-injections")
    p.add_argument("provider_args", nargs=argparse.REMAINDER)
    p.set_defaults(func=_provider_command)

    p = sub.add_parser("clean", help="Remove generated project-local index assets")
    p.add_argument("--include-repo-injections", action="store_true")
    p.set_defaults(func=lambda args: clean_mod.clean(_project_root(args.project_root), include_repo_injections=args.include_repo_injections))

    p = sub.add_parser("validate-skills", help="Validate installed skill assets")
    p.add_argument("--skills-root", default=None, help="Skills root to validate. Defaults to <project-root>/.agents/skills.")
    p.set_defaults(func=lambda args: validate_skills(Path(args.skills_root).resolve() if args.skills_root else _project_root(args.project_root) / ".agents" / "skills"))

    p = sub.add_parser("show", help="Print derived project configuration")
    p.set_defaults(func=lambda args: _show(_project_root(args.project_root)))
    return parser


def _provider_command(args: argparse.Namespace) -> int:
    root = _project_root(args.project_root)
    data = load_manifest(root)
    provider = get_provider(args.provider)
    return provider.run(root, data, args.action, args.provider_args)


def _show(project_root: Path) -> int:
    data = load_manifest(project_root)
    providers = [name for name, _ in ((data.get("providers") or {}).items()) if isinstance(_, dict) and _.get("enabled", True)]
    print(f"project_root: {project_root}")
    print(f"manifest: {project_root / '.agent-index' / 'agent-index.yaml'}")
    print(f"providers: {', '.join(providers)}")
    print(f"repos: {len(data.get('repos', []))}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args) or 0)
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        print(f"agent-index: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
