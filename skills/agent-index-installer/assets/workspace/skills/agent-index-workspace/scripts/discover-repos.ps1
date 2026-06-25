param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function ConvertTo-StableName {
  param([string]$Value)
  $name = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
  return $name.Trim('-')
}

function ConvertTo-RelativePath {
  param([string]$Root, [string]$FullPath)

  $rootPath = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\', '/')
  $targetPath = (Resolve-Path -LiteralPath $FullPath).Path.TrimEnd('\', '/')
  if ($targetPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
    return '.'
  }

  $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
  if (-not $targetPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Path is outside project root: $targetPath"
  }

  return ($targetPath.Substring($prefix.Length) -replace '\\', '/')
}

function Get-ProjectName {
  param([string]$Root)
  $manifest = Join-Path $Root '.agent-index\agent-index.yaml'
  if (Test-Path -LiteralPath $manifest) {
    foreach ($line in Get-Content -LiteralPath $manifest) {
      if ($line -match '^\s*project:\s*(.+?)\s*$') {
        return (ConvertTo-StableName $Matches[1].Trim("'`""))
      }
    }
  }
  return (ConvertTo-StableName (Split-Path -Leaf $Root))
}

function Get-WorkspaceConfig {
  param([string]$Root)

  $config = [ordered]@{
    RepoRoots = @('.')
    Recursive = $false
    MaxDepth = 1
    ExcludeDirs = @('.agent-index', '.agents', '.codex', '.codegraph', '.gitnexus', '.understand-anything', 'node_modules')
  }

  $manifest = Join-Path $Root '.agent-index\agent-index.yaml'
  if (-not (Test-Path -LiteralPath $manifest)) {
    return $config
  }

  $lines = @(Get-Content -LiteralPath $manifest)
  $insideWorkspace = $false
  $insideDiscovery = $false
  $insideRepoRoots = $false
  $insideExcludeDirs = $false
  $repoRoots = @()
  $excludeDirs = @()

  foreach ($line in $lines) {
    if ($line -match '^workspace:\s*$') {
      $insideWorkspace = $true
      $insideDiscovery = $false
      $insideRepoRoots = $false
      $insideExcludeDirs = $false
      continue
    }
    if ($insideWorkspace -and $line -match '^[A-Za-z0-9_-]+:\s*') {
      break
    }
    if (-not $insideWorkspace) {
      continue
    }

    if ($line -match '^\s{2}repo_roots:\s*$') {
      $insideDiscovery = $false
      $insideRepoRoots = $true
      $insideExcludeDirs = $false
      continue
    }
    if ($line -match '^\s{2}exclude_dirs:\s*$') {
      $insideDiscovery = $false
      $insideRepoRoots = $false
      $insideExcludeDirs = $true
      continue
    }
    if ($line -match '^\s{2}discovery:\s*$') {
      $insideDiscovery = $true
      $insideRepoRoots = $false
      $insideExcludeDirs = $false
      continue
    }
    if ($line -match '^\s{2}recursive:\s*(true|false)\s*$') {
      $config.Recursive = [bool]::Parse($Matches[1])
      $insideDiscovery = $false
      $insideRepoRoots = $false
      $insideExcludeDirs = $false
      continue
    }
    if ($line -match '^\s{2}max_depth:\s*(\d+)\s*$') {
      $config.MaxDepth = [int]$Matches[1]
      $insideDiscovery = $false
      $insideRepoRoots = $false
      $insideExcludeDirs = $false
      continue
    }
    if ($insideDiscovery -and $line -match '^\s{4}recursive:\s*(true|false)\s*$') {
      $config.Recursive = [bool]::Parse($Matches[1])
      continue
    }
    if ($insideDiscovery -and $line -match '^\s{4}max_depth:\s*(\d+)\s*$') {
      $config.MaxDepth = [int]$Matches[1]
      continue
    }
    if ($insideRepoRoots -and $line -match '^\s{4}-\s+(.+?)\s*$') {
      $repoRoots += $Matches[1].Trim("'`"")
      continue
    }
    if ($insideExcludeDirs -and $line -match '^\s{4}-\s+(.+?)\s*$') {
      $excludeDirs += $Matches[1].Trim("'`"")
      continue
    }
  }

  if ($repoRoots.Count -gt 0) {
    $config.RepoRoots = @($repoRoots)
  }
  if ($excludeDirs.Count -gt 0) {
    $config.ExcludeDirs = @($excludeDirs)
  }

  return $config
}

function Find-GitRepos {
  param(
    [string]$Root,
    [string]$RepoRoot,
    [bool]$Recursive,
    [int]$MaxDepth,
    [string[]]$ExcludeDirs
  )

  $start = if ([IO.Path]::IsPathRooted($RepoRoot)) {
    (Resolve-Path -LiteralPath $RepoRoot).Path
  } else {
    (Resolve-Path -LiteralPath (Join-Path $Root ($RepoRoot -replace '/', '\'))).Path
  }

  $repos = New-Object System.Collections.Generic.List[object]

  function Add-Repo {
    param([string]$RepoPath)
    $relative = ConvertTo-RelativePath -Root $Root -FullPath $RepoPath
    $repoName = ConvertTo-StableName $relative
    $repos.Add([pscustomobject]@{
      path = $relative
      name = "$projectName-$repoName"
      fullPath = (Resolve-Path -LiteralPath $RepoPath).Path
    })
  }

  if (Test-Path -LiteralPath (Join-Path $start '.git')) {
    Add-Repo -RepoPath $start
    return @($repos.ToArray())
  }

  function Visit-Children {
    param([string]$Directory, [int]$Depth)

    if ($Depth -gt $MaxDepth) {
      return
    }

    foreach ($child in Get-ChildItem -LiteralPath $Directory -Force -Directory | Sort-Object FullName) {
      if ($ExcludeDirs -contains $child.Name) {
        continue
      }
      if (Test-Path -LiteralPath (Join-Path $child.FullName '.git')) {
        Add-Repo -RepoPath $child.FullName
        continue
      }
      if ($Recursive) {
        Visit-Children -Directory $child.FullName -Depth ($Depth + 1)
      }
    }
  }

  Visit-Children -Directory $start -Depth 1
  return @($repos.ToArray())
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projectName = Get-ProjectName -Root $root
$workspace = Get-WorkspaceConfig -Root $root

$repos = @()
foreach ($repoRoot in $workspace.RepoRoots) {
  $repos += Find-GitRepos -Root $root -RepoRoot $repoRoot -Recursive:$workspace.Recursive -MaxDepth $workspace.MaxDepth -ExcludeDirs $workspace.ExcludeDirs
}

$repos = @($repos | Sort-Object path -Unique)

$repos | ConvertTo-Json -Depth 3
