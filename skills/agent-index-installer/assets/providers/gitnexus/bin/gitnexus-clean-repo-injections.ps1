param(
  [string[]]$Repo = @(),
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$AgentIndexDir = Split-Path -Parent $PSScriptRoot
$ProjectRoot = Split-Path -Parent $AgentIndexDir
$env:XDG_CONFIG_HOME = Join-Path $AgentIndexDir "xdg-config"
New-Item -ItemType Directory -Force -Path $env:XDG_CONFIG_HOME | Out-Null
$ProjectGitIgnore = Join-Path $env:XDG_CONFIG_HOME "git\ignore"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProjectGitIgnore) | Out-Null
if (-not (Test-Path -LiteralPath $ProjectGitIgnore)) {
  New-Item -ItemType File -Force -Path $ProjectGitIgnore | Out-Null
}
$ProjectGitIgnoreSafe = $ProjectGitIgnore -replace "\\", "/"

function Resolve-StrictPath([string]$Path) {
  return (Resolve-Path -LiteralPath $Path).Path.TrimEnd("\", "/")
}

function Test-PathUnder([string]$Child, [string]$Parent) {
  $normalizedChild = $Child.TrimEnd("\", "/")
  $normalizedParent = $Parent.TrimEnd("\", "/")
  if ($normalizedChild.Equals($normalizedParent, [StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }
  $prefix = $normalizedParent + [IO.Path]::DirectorySeparatorChar
  return $normalizedChild.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Resolve-RepoPath([string]$RepoArg) {
  $candidate = $RepoArg
  if (-not [IO.Path]::IsPathRooted($candidate)) {
    $candidate = Join-Path $ProjectRoot $candidate
  }
  $resolved = Resolve-StrictPath $candidate
  if (-not (Test-Path -LiteralPath (Join-Path $resolved ".git"))) {
    throw "Not a git repo: $RepoArg"
  }
  return $resolved
}

function Get-ManifestRepoPaths([string]$Root) {
  $manifest = Join-Path $Root ".agent-index\agent-index.yaml"
  if (-not (Test-Path -LiteralPath $manifest)) {
    return @()
  }

  $repoPaths = @()
  $insideRepos = $false
  foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -match "^repos:\s*(\[\])?\s*$") {
      $insideRepos = $true
      continue
    }
    if ($insideRepos -and $line -match "^[A-Za-z0-9_-]+:\s*") {
      break
    }
    if ($insideRepos -and $line -match "^\s*-\s+path:\s*(.+?)\s*$") {
      $repoPaths += $Matches[1].Trim("'`"")
    }
  }
  return @($repoPaths)
}

$ProjectRootResolved = Resolve-StrictPath $ProjectRoot

if ($Repo.Count -gt 0) {
  $RepoPaths = $Repo | ForEach-Object { Resolve-RepoPath $_ }
} else {
  $manifestRepoPaths = @(Get-ManifestRepoPaths -Root $ProjectRootResolved)
  if ($manifestRepoPaths.Count -gt 0) {
    $RepoPaths = $manifestRepoPaths | ForEach-Object { Resolve-RepoPath $_ }
  } else {
    $RepoPaths = Get-ChildItem -LiteralPath $ProjectRootResolved -Force -Directory |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ".git") } |
      ForEach-Object { $_.FullName }
  }
}

foreach ($repoPath in $RepoPaths) {
  $repoRoot = Resolve-StrictPath $repoPath
  if (-not (Test-PathUnder $repoRoot $ProjectRootResolved)) {
    throw "Refusing to clean outside project root: $repoRoot"
  }
  $safeRepoRoot = $repoRoot -replace "\\", "/"

  foreach ($relative in @(".claude/skills/gitnexus", ".claude/skills/generated")) {
    $target = Join-Path $repoRoot ($relative -replace "/", [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $target)) {
      continue
    }

    $targetResolved = Resolve-StrictPath $target
    if (-not (Test-PathUnder $targetResolved $repoRoot)) {
      throw "Refusing to clean outside repo root: $targetResolved"
    }

    $tracked = & git -c "safe.directory=$safeRepoRoot" -c "core.excludesFile=$ProjectGitIgnoreSafe" -C $repoRoot ls-files -- $relative 2>$null
    if ($tracked) {
      Write-Host "[skip tracked] $repoRoot\$relative"
      continue
    }

    if ($DryRun) {
      Write-Host "[dry-run remove] $targetResolved"
    } else {
      Remove-Item -LiteralPath $targetResolved -Recurse -Force
      Write-Host "[removed] $targetResolved"
    }

    foreach ($emptyCandidate in @(
      (Join-Path $repoRoot ".claude\skills"),
      (Join-Path $repoRoot ".claude")
    )) {
      if ((Test-Path -LiteralPath $emptyCandidate) -and
          -not (Get-ChildItem -LiteralPath $emptyCandidate -Force | Select-Object -First 1)) {
        if ($DryRun) {
          Write-Host "[dry-run remove empty] $emptyCandidate"
        } else {
          Remove-Item -LiteralPath $emptyCandidate -Force
          Write-Host "[removed empty] $emptyCandidate"
        }
      }
    }
  }
}
