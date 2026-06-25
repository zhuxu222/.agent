from __future__ import annotations

from .manifest import enabled_providers, load_manifest
from .providers import get_provider


def run(project_root, action: str, extra: list[str] | None = None) -> int:
    data = load_manifest(project_root)
    providers = enabled_providers(data)
    if not providers:
        print("No enabled index providers in .agent-index/agent-index.yaml")
        return 0

    rc = 0
    for name, _settings in providers:
        provider = get_provider(name)
        print(f"== {name}: {action} ==")
        code = provider.run(project_root, data, action, extra or [])
        if code != 0:
            rc = code
            if action not in {"status", "validate"}:
                break
    return rc
