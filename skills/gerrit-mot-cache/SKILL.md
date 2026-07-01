---
name: gerrit-mot-cache
description: Use when cloning, fetching, pulling, validating, repairing, inspecting, or review-pushing Git repositories under https://gerrit.mot.com/ or ssh://*.gerrit.mot.com:29418. Use the local master-only bare cache, clone worktrees with --reference-if-able, keep worktree origin pointed at Gerrit, update cache master before fetch/pull, push only reviews to refs/for/master, never push directly to master, and stop on master non-fast-forward violations.
---

# Gerrit MOT Cache

Use this skill for Git repositories hosted under `https://gerrit.mot.com/` or `ssh://*.gerrit.mot.com:29418`.

## Core Rules

- Use `scripts/gerrit_cache.py` before cloning, fetching, pulling, validating, or repairing Gerrit worktrees.
- `scripts/gerrit-cache.ps1` and `scripts/gerrit-cache.sh` are thin wrappers around the Python implementation.
- Store cache repositories as bare repositories containing only `refs/heads/master`.
- Cache root precedence is `--cache-root`, then `GERRIT_MOT_CACHE_ROOT`, then the platform default.
- Windows default cache root is `D:\common\solution\lenovo\gerrit\cache\gerrit.mot.com`.
- Ubuntu/Linux default cache root is `/data/solution/lenovo/gerrit/cache/gerrit.mot.com`.
- If the cache root cannot be created or written, stop and ask the user to set `GERRIT_MOT_CACHE_ROOT`; do not silently fall back to another cache.
- Do not mirror tags, review refs, or non-master branches into the cache.
- Do not reuse old legacy caches; old cache locations are obsolete.
- Clone worktrees with `git clone --reference-if-able <cache.git> --single-branch --branch master --no-tags <gerrit-url> <worktree>`, then refresh cache and worktree `origin/master` again to close races where Gerrit `master` advances during clone.
- Keep worktree fetch refspec limited to `+refs/heads/master:refs/remotes/origin/master`.
- Enable worktree `core.longpaths=true` because some Gerrit repositories contain paths longer than the Windows default limit.
- Keep worktree `origin.url` pointed at Gerrit, not at the cache.
- Push changes only as Gerrit reviews with `git push origin HEAD:refs/for/master`.
- Never run direct pushes to `master`, including `git push origin master`, `git push origin HEAD:master`, or `git push origin HEAD:refs/heads/master`.
- Treat a non-fast-forward move of `refs/heads/master` as a Gerrit policy violation. Stop and report it.
- If clone fails after creating a new worktree path, remove only that newly-created partial worktree after verifying it has a `.git` marker.
- Do not delete worktree files, reset user branches, or recreate user worktrees as the default response to a cache problem.
- Reject Gerrit URL paths that contain unsafe decoded segments such as `.`, `..`, empty path parts, backslashes, Windows drive prefixes, NUL bytes, or absolute paths.

## Commands

Use the bundled Python script from this skill folder.

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\gerrit-cache.ps1 clone <gerrit-url> <worktree>
powershell -ExecutionPolicy Bypass -File .\scripts\gerrit-cache.ps1 update-cache <gerrit-url>
powershell -ExecutionPolicy Bypass -File .\scripts\gerrit-cache.ps1 pull <worktree>
powershell -ExecutionPolicy Bypass -File .\scripts\gerrit-cache.ps1 fetch <worktree>
powershell -ExecutionPolicy Bypass -File .\scripts\gerrit-cache.ps1 validate <worktree>
powershell -ExecutionPolicy Bypass -File .\scripts\gerrit-cache.ps1 repair <worktree>
powershell -ExecutionPolicy Bypass -File .\scripts\gerrit-cache.ps1 push-review <worktree>
```

Ubuntu/POSIX:

```sh
sh ./scripts/gerrit-cache.sh clone <gerrit-url> <worktree>
sh ./scripts/gerrit-cache.sh update-cache <gerrit-url>
sh ./scripts/gerrit-cache.sh pull <worktree>
sh ./scripts/gerrit-cache.sh fetch <worktree>
sh ./scripts/gerrit-cache.sh validate <worktree>
sh ./scripts/gerrit-cache.sh repair <worktree>
sh ./scripts/gerrit-cache.sh push-review <worktree>
```

Direct Python invocation:

```text
python scripts/gerrit_cache.py clone <gerrit-url> <worktree>
python scripts/gerrit_cache.py update-cache <gerrit-url>
python scripts/gerrit_cache.py pull <worktree>
python scripts/gerrit_cache.py fetch <worktree>
python scripts/gerrit_cache.py validate <worktree>
python scripts/gerrit_cache.py repair <worktree>
python scripts/gerrit_cache.py push-review <worktree>
```

For the common `readyforassist` case:

```powershell
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.agents\skills\gerrit-mot-cache\scripts\gerrit-cache.ps1" clone "https://gerrit.mot.com/home/repo/dev/apps/win/readyforassist" "D:\common\solution\lenovo\2025\super_resolution\repo\win\readyforassist"
```

Ubuntu equivalent:

```sh
python3 "$HOME/.agents/skills/gerrit-mot-cache/scripts/gerrit_cache.py" clone "https://gerrit.mot.com/home/repo/dev/apps/win/readyforassist" "/data/solution/lenovo/2025/super_resolution/repo/win/readyforassist"
```

## Workflow

For clone:

1. Resolve the Gerrit URL to the matching cache path.
2. Create the cache with `git clone --bare --single-branch --branch master --no-tags` if it is missing.
3. Do not read from obsolete legacy cache paths.
4. Update the cache if it exists.
5. Check that `master` only moves fast-forward.
6. Clone the worktree from Gerrit with `--reference-if-able <cache.git> --single-branch --branch master --no-tags`.
7. Set worktree long-path, master-only fetch, and no-tags config.
8. Refresh the cache and fetch worktree `origin/master` again; retry briefly until cache `master` and worktree `origin/master` match.
9. Fast-forward local `master` to `origin/master`.
10. Confirm alternates points at the cache.
11. If clone fails, clean up only the partial worktree created by this clone attempt.

For fetch or pull:

1. Read the worktree `origin.url`.
2. Update the corresponding master-only cache.
3. Check that `master` only moves fast-forward.
4. Fetch only `refs/heads/master` into worktree `origin/master`.
5. Retry briefly until cache `master` and worktree `origin/master` match, because Gerrit can advance during the operation.
6. For `pull`, fast-forward the local branch only when the current branch is `master`; on feature branches, fetch `origin/master` only and require an explicit rebase or merge.

For validation:

1. Confirm the worktree origin points at Gerrit.
2. Confirm `.git/objects/info/alternates` points at the cache objects directory.
3. Run `git fsck --connectivity-only --no-dangling` unless the user explicitly skips it.

For push:

1. Confirm the worktree origin points at Gerrit.
2. Push the current commit only to `refs/for/master`.
3. Do not push to `master` or `refs/heads/master` directly.

Read `references/policy.md` when changing this workflow or explaining the cache safety model.
