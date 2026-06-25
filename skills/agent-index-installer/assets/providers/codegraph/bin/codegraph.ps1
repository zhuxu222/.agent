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

function Get-SafeGitDirs([string]$Root) {
  $dirs = @(Resolve-Path -LiteralPath $Root | ForEach-Object { $_.Path })
  $repoPaths = @(Get-ManifestRepoPaths -Root $Root)
  if ($repoPaths.Count -gt 0) {
    foreach ($repoPath in $repoPaths) {
      $candidate = if ([IO.Path]::IsPathRooted($repoPath)) {
        $repoPath
      } else {
        Join-Path $Root ($repoPath -replace "/", "\")
      }
      if (Test-Path -LiteralPath (Join-Path $candidate ".git")) {
        $dirs += (Resolve-Path -LiteralPath $candidate).Path
      }
    }
  } else {
    $dirs += Get-ChildItem -LiteralPath $Root -Force -Directory |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ".git") } |
      ForEach-Object { $_.FullName }
  }
  return @($dirs | Sort-Object -Unique)
}

$SafeGitDirs = Get-SafeGitDirs -Root $ProjectRoot
$GitConfigEntries = @()
foreach ($safeGitDir in $SafeGitDirs) {
  $GitConfigEntries += [pscustomobject]@{
    Key = "safe.directory"
    Value = ($safeGitDir -replace "\\", "/")
  }
}
$GitConfigEntries += [pscustomobject]@{
  Key = "core.excludesFile"
  Value = ($ProjectGitIgnore -replace "\\", "/")
}
$env:GIT_CONFIG_COUNT = [string]$GitConfigEntries.Count
for ($i = 0; $i -lt $GitConfigEntries.Count; $i++) {
  Set-Item -Path "Env:GIT_CONFIG_KEY_$i" -Value $GitConfigEntries[$i].Key
  Set-Item -Path "Env:GIT_CONFIG_VALUE_$i" -Value $GitConfigEntries[$i].Value
}

$CodeGraph = Get-Command codegraph.cmd -ErrorAction SilentlyContinue
if (-not $CodeGraph) {
  $CodeGraph = Get-Command codegraph -ErrorAction Stop
}

Push-Location $ProjectRoot
try {
  & $CodeGraph.Source @args
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
