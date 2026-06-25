from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

FRONTMATTER = re.compile(r"^---\s*\n(.+?)\n---\s*\n", re.DOTALL)
NAME = re.compile(r"^name:\s*[a-z0-9][a-z0-9-]*\s*$", re.MULTILINE)
DESCRIPTION = re.compile(r"^description:\s*.+$", re.MULTILINE)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def add(errors: list[str], message: str) -> None:
    errors.append(message)


def validate_directory_links(root: Path, errors: list[str]) -> None:
    for child in root.iterdir():
        if child.is_dir() and child.is_symlink() and not child.exists():
            add(errors, f"Broken directory link: {child}")


def validate_skill_frontmatter(root: Path, errors: list[str]) -> None:
    for path in root.rglob("SKILL.md"):
        content = read_text(path)
        match = FRONTMATTER.search(content)
        if not match:
            add(errors, f"Missing YAML frontmatter: {path}")
            continue
        frontmatter = match.group(1)
        if not NAME.search(frontmatter):
            add(errors, f"Missing or invalid skill name: {path}")
        if not DESCRIPTION.search(frontmatter):
            add(errors, f"Missing description: {path}")


def validate_openai_yaml(root: Path, errors: list[str]) -> None:
    for path in root.rglob("openai.yaml"):
        content = read_text(path)
        if not re.search(r"^interface:\s*$", content, re.MULTILINE):
            add(errors, f"openai.yaml missing interface block: {path}")
        for field in ["display_name", "short_description", "default_prompt"]:
            pattern = r'^\s{2}' + re.escape(field) + r': ".+"\s*$'
            if not re.search(pattern, content, re.MULTILINE):
                add(errors, f"openai.yaml missing quoted interface.{field}: {path}")
        skill_dir = path.parent.parent
        token = "$" + skill_dir.name
        if token not in content:
            add(errors, f"openai.yaml default_prompt should mention {token}: {path}")


def validate_python(root: Path, errors: list[str]) -> None:
    for path in root.rglob("*.py"):
        if any(part in {".venv", ".git", "__pycache__"} for part in path.parts):
            continue
        try:
            compile(read_text(path), str(path), "exec")
        except SyntaxError as exc:
            add(errors, f"Python syntax error: {path}:{exc.lineno}: {exc.msg}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate local skills")
    default_root = Path(__file__).resolve().parents[1] / "skills"
    parser.add_argument("--skills-root", default=str(default_root))
    args = parser.parse_args(argv)

    root = Path(args.skills_root).resolve()
    errors: list[str] = []
    if not root.exists():
        errors.append(f"Skills root does not exist: {root}")
    else:
        validate_directory_links(root, errors)
        validate_skill_frontmatter(root, errors)
        validate_openai_yaml(root, errors)
        validate_python(root, errors)

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(f"Skill validation failed with {len(errors)} error(s).", file=sys.stderr)
        return 1

    print(f"Skill validation OK: {root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
