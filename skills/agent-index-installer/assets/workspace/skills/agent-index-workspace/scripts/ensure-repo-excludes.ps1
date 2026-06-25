param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string[]]$Patterns = @('.codegraph/', '.gitnexus/', '.understand-anything/')
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectPath {
  param([string]$Root, [string]$Relative)
  if ([IO.Path]::IsPathRooted($Relative)) {
    return (Resolve-Path -LiteralPath $Relative).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $Root ($Relative -replace '/', '\'))).Path
}

function Get-ManifestRepoPaths {
  param([string]$ManifestPath)

  $paths = @()
  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^\s*-\s+path:\s*(.+?)\s*$') {
      $paths += $Matches[1].Trim("'`"")
    }
  }
  return @($paths)
}

function Get-GitDir {
  param([string]$RepoPath)

  $gitPath = Join-Path $RepoPath '.git'
  if (Test-Path -LiteralPath $gitPath -PathType Container) {
    return (Resolve-Path -LiteralPath $gitPath).Path
  }

  if (Test-Path -LiteralPath $gitPath -PathType Leaf) {
    $content = Get-Content -LiteralPath $gitPath -TotalCount 1
    if ($content -match '^gitdir:\s*(.+?)\s*$') {
      $gitDir = $Matches[1].Trim()
      if (-not [IO.Path]::IsPathRooted($gitDir)) {
        $gitDir = Join-Path $RepoPath $gitDir
      }
      return (Resolve-Path -LiteralPath $gitDir).Path
    }
  }

  throw "Not a git repo: $RepoPath"
}

function Ensure-ExcludePatterns {
  param(
    [string]$RepoPath,
    [string[]]$Patterns
  )

  $gitDir = Get-GitDir -RepoPath $RepoPath
  $infoDir = Join-Path $gitDir 'info'
  $excludePath = Join-Path $infoDir 'exclude'
  New-Item -ItemType Directory -Force -Path $infoDir | Out-Null

  $existing = @()
  if (Test-Path -LiteralPath $excludePath) {
    $existing = @(Get-Content -LiteralPath $excludePath)
  }

  $missing = @($Patterns | Where-Object { $existing -notcontains $_ })
  if ($missing.Count -eq 0) {
    Write-Host "Repo excludes OK: $RepoPath"
    return
  }

  $newLines = New-Object System.Collections.Generic.List[string]
  foreach ($line in $existing) {
    $newLines.Add($line)
  }
  if (($newLines.Count -gt 0) -and ($newLines[$newLines.Count - 1] -ne '')) {
    $newLines.Add('')
  }
  if ($existing -notcontains '# agent-index local indexes') {
    $newLines.Add('# agent-index local indexes')
  }
  foreach ($pattern in $missing) {
    $newLines.Add($pattern)
  }

  Set-Content -LiteralPath $excludePath -Value $newLines -Encoding UTF8
  Write-Host "Updated repo excludes: $RepoPath"
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$manifest = Join-Path $root '.agent-index\agent-index.yaml'
if (-not (Test-Path -LiteralPath $manifest)) {
  throw "Missing manifest: $manifest"
}

$repoPaths = @(Get-ManifestRepoPaths -ManifestPath $manifest)
if ($repoPaths.Count -eq 0) {
  throw 'No repos configured.'
}

foreach ($repoPath in $repoPaths) {
  $full = Resolve-ProjectPath -Root $root -Relative $repoPath
  if (-not $full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to update excludes outside project root: $full"
  }
  Ensure-ExcludePatterns -RepoPath $full -Patterns $Patterns
}
