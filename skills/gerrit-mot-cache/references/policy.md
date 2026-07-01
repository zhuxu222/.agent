# Gerrit MOT Cache Policy

## Goal

Optimize Gerrit clone and pull performance while reducing per-worktree Git object storage.

This workflow is an acceleration and disk-saving policy, not an isolation policy. Worktree remotes remain pointed at Gerrit.

## Assumptions

- `master` is the primary development branch.
- `master` accepts changes only through Gerrit review.
- Direct pushes to `master` are not allowed.
- `master` must move forward only.
- Other remote branches may exist, but local development branches are created from `master`.
- Cache repositories contain only `refs/heads/master`; tags, review refs, and non-master branches are not mirrored.

## Cache Shape

Each Gerrit repository maps to one master-only bare cache:

```text
<cache-root>/<gerrit-repo-path>.git
```

Cache root precedence:

```text
--cache-root
GERRIT_MOT_CACHE_ROOT
platform default
```

Platform defaults:

```text
Windows:      D:\common\solution\lenovo\gerrit\cache\gerrit.mot.com
Ubuntu/Linux: /data/solution/lenovo/gerrit/cache/gerrit.mot.com
```

Examples:

```text
https://gerrit.mot.com/home/repo/dev/apps/win/readyforassist
D:\common\solution\lenovo\gerrit\cache\gerrit.mot.com\home\repo\dev\apps\win\readyforassist.git
/data/solution/lenovo/gerrit/cache/gerrit.mot.com/home/repo/dev/apps/win/readyforassist.git
```

The helper must reject decoded repository paths containing `.`, `..`, empty path parts, backslashes, Windows drive prefixes, NUL bytes, or absolute paths. The final cache path must resolve under the configured cache root before any directory is created.

## Worktree Shape

Worktrees are cloned from Gerrit, with the cache supplied as a reference:

```text
git clone --reference-if-able <cache.git> --single-branch --branch master --no-tags <gerrit-url> <worktree>
```

Expected result:

```text
origin.url = <gerrit-url>
remote.origin.fetch = +refs/heads/master:refs/remotes/origin/master
remote.origin.tagOpt = --no-tags
.git/objects/info/alternates = <cache.git>/objects
core.longpaths = true
```

## Review Push Policy

Push changes only as Gerrit reviews:

```text
git push origin HEAD:refs/for/master
```

Do not push directly to `master`:

```text
git push origin master
git push origin HEAD:master
git push origin HEAD:refs/heads/master
```

The local cache is never a push target. Worktree `origin.url` must remain pointed at Gerrit.

## GC Policy

Automatic cache GC may remain enabled. With a forward-only `master`, GC should not remove objects that are reachable from `master`. Objects reachable only from non-master refs are intentionally outside this cache policy.

Do not run aggressive manual pruning on the shared cache unless every dependent worktree has been checked:

```text
git gc --prune=now
git prune
git repack -Ad
```

## Failure Handling

If cache `master` detects a non-fast-forward move, stop and report a Gerrit policy violation. Do not hide this by deleting worktrees, resetting user branches, or force-updating local development branches.

If the cache is missing or corrupt, rebuild the cache and run `validate` or `repair` on affected worktrees. Current checked-out files should not be deleted as part of cache repair.

If a clone operation fails after creating the requested worktree path, remove only that newly-created partial worktree and only after verifying it contains a `.git` marker. Never delete an existing worktree as a generic repair step.

## Cross-Platform Implementation

The Python script `scripts/gerrit_cache.py` is the single source of truth for URL parsing, path safety, locking, Git commands, clone, fetch, pull, validate, repair, and review push behavior.

`scripts/gerrit-cache.ps1` and `scripts/gerrit-cache.sh` are only argument-forwarding wrappers. Do not reintroduce separate platform-specific cache logic into either wrapper.
