from __future__ import annotations

from pathlib import Path

PROJECT_REQUIRED_SKILLS = {
    "agent-index-router": ["SKILL.md"],
    "agent-index-workspace": ["SKILL.md"],
    "agent-index-lifecycle": ["SKILL.md"],
    "agent-index-codegraph": ["SKILL.md"],
    "agent-codegraph-usage": ["SKILL.md"],
    "agent-index-gitnexus": ["SKILL.md"],
    "agent-gitnexus-usage": ["SKILL.md"],
}

SOURCE_ONLY_SKILLS = {
    "agent-index-installer": ["SKILL.md", "assets"],
}


def _find_skill(skills_root: Path, name: str) -> Path | None:
    direct = skills_root / name
    if direct.exists():
        return direct
    matches = list(skills_root.rglob(name))
    dirs = [p for p in matches if p.is_dir()]
    return dirs[0] if dirs else None


def _check(skills_root: Path, required: dict[str, list[str]]) -> list[str]:
    missing: list[str] = []
    for name, files in required.items():
        path = _find_skill(skills_root, name)
        if path is None:
            missing.append(f"{name}/")
            continue
        for rel in files:
            if not (path / rel).exists():
                missing.append(f"{name}/{rel}")
    return missing


def validate_skills(skills_root: Path) -> int:
    missing = _check(skills_root, PROJECT_REQUIRED_SKILLS)
    for name, files in SOURCE_ONLY_SKILLS.items():
        if _find_skill(skills_root, name) is not None:
            missing.extend(_check(skills_root, {name: files}))

    if missing:
        print("Missing required skill assets:")
        for item in missing:
            print(f"  - {item}")
        return 1
    print("Skill assets OK")
    return 0
