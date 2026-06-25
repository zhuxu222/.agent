param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string[]]$RepoFilter = @(),
  [switch]$Force,
  [int]$WorkerTimeout = 120,
  [int]$MaxFileSize = 256
)

$ErrorActionPreference = 'Stop'

function Get-ManifestRepos {
  param([string]$ManifestPath)

  $repos = @()
  $currentPath = $null
  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^\s*-\s+path:\s*(.+?)\s*$') {
      $currentPath = $Matches[1].Trim("'`"")
      $repos += [pscustomobject]@{ Path = $currentPath; Name = $currentPath }
      continue
    }
    if ($null -ne $currentPath -and $line -match '^\s*name:\s*(.+?)\s*$') {
      $repos[-1].Name = $Matches[1].Trim("'`"")
      $currentPath = $null
    }
  }
  return $repos
}

function Get-ManifestGroup {
  param([string]$ManifestPath)

  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^\s*group:\s*(.+?)\s*$') {
      return $Matches[1].Trim("'`"")
    }
  }
  return $null
}

function ConvertTo-Kilobytes {
  param([string]$Value)

  $normalized = $Value.Trim("'`"").Trim()
  if ($normalized -match '^(\d+)\s*(k|kb)?$') {
    return [int]$Matches[1]
  }
  if ($normalized -match '^(\d+)\s*(m|mb)$') {
    return ([int]$Matches[1]) * 1024
  }
  throw "Unsupported size value: $Value"
}

function Get-GitNexusMaxFileSize {
  param([string]$ManifestPath)

  $insideGitNexus = $false
  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^\s{2}gitnexus:\s*$') {
      $insideGitNexus = $true
      continue
    }
    if ($insideGitNexus -and $line -match '^\s{2}[A-Za-z0-9_-]+:\s*$') {
      break
    }
    if (-not $insideGitNexus) {
      continue
    }
    if ($line -match '^\s{4}max_file_size(_kb)?:\s*(.+?)\s*$') {
      return ConvertTo-Kilobytes $Matches[2]
    }
  }

  return $null
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$manifest = Join-Path $root '.agent-index\agent-index.yaml'
$wrapper = Join-Path $root '.agent-index\bin\gitnexus.ps1'
$cleanup = Join-Path $root '.agent-index\bin\gitnexus-clean-repo-injections.ps1'

if (-not (Test-Path -LiteralPath $manifest)) {
  throw "Missing manifest: $manifest"
}
if (-not (Test-Path -LiteralPath $wrapper)) {
  throw "Missing GitNexus wrapper: $wrapper"
}

if (-not $PSBoundParameters.ContainsKey('MaxFileSize')) {
  $configuredMaxFileSize = Get-GitNexusMaxFileSize -ManifestPath $manifest
  if ($configuredMaxFileSize) {
    $MaxFileSize = $configuredMaxFileSize
  }
}

$manifestRepos = Get-ManifestRepos -ManifestPath $manifest
if ($RepoFilter.Count -gt 0) {
  $selected = @($manifestRepos | Where-Object { $RepoFilter -contains $_.Path -or $RepoFilter -contains $_.Name })
} else {
  $selected = @($manifestRepos)
}
if ($selected.Count -eq 0) {
  throw "No repos selected from manifest: $manifest"
}

foreach ($repoEntry in $selected) {
  $fullRepo = Join-Path $root $repoEntry.Path
  if (-not (Test-Path -LiteralPath $fullRepo)) {
    throw "Repo path does not exist: $fullRepo"
  }

  $args = @('analyze', $fullRepo, '--skip-agents-md', '--name', $repoEntry.Name, '--worker-timeout', "$WorkerTimeout", '--max-file-size', "$MaxFileSize")
  if ($Force) {
    $args += '--force'
  }

  Write-Host "GitNexus analyze: $($repoEntry.Path) as $($repoEntry.Name)"
  & $wrapper @args
  if ($LASTEXITCODE -ne 0) {
    throw "GitNexus analyze failed for $($repoEntry.Path) with exit code $LASTEXITCODE"
  }
}

$group = Get-ManifestGroup -ManifestPath $manifest
if ($group) {
  Write-Host "GitNexus group sync: $group"
  & $wrapper group sync $group --skip-embeddings
  if ($LASTEXITCODE -ne 0) {
    throw "GitNexus group sync failed for $group with exit code $LASTEXITCODE"
  }
}

if (Test-Path -LiteralPath $cleanup) {
  & $cleanup
  if ($LASTEXITCODE -ne 0) {
    throw "GitNexus cleanup failed with exit code $LASTEXITCODE"
  }
}
