param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string[]]$Repo = @()
)

$ErrorActionPreference = 'Stop'

function Get-ManifestRepos {
  param([string]$ManifestPath)

  $repos = @()
  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^\s*-\s+path:\s*(.+?)\s*$') {
      $repos += $Matches[1].Trim("'`"")
    }
  }
  return $repos
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$manifest = Join-Path $root '.agent-index\agent-index.yaml'
$wrapper = Join-Path $root '.agent-index\bin\codegraph.ps1'

if (-not (Test-Path -LiteralPath $manifest)) {
  throw "Missing manifest: $manifest"
}
if (-not (Test-Path -LiteralPath $wrapper)) {
  throw "Missing CodeGraph wrapper: $wrapper"
}

$repos = if ($Repo.Count -gt 0) { $Repo } else { Get-ManifestRepos -ManifestPath $manifest }
if ($repos.Count -eq 0) {
  throw "No repos found in manifest: $manifest"
}

$failures = @()
foreach ($repoPath in $repos) {
  $fullRepo = Join-Path $root $repoPath
  Write-Host "CodeGraph status: $repoPath"
  & $wrapper status $fullRepo
  if ($LASTEXITCODE -ne 0) {
    $failures += "$repoPath exit=$LASTEXITCODE"
  }
}

if ($failures.Count -gt 0) {
  throw "CodeGraph validation failed: $($failures -join ', ')"
}
