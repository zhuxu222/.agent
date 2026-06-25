param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Resolve-ProjectPath {
  param([string]$Root, [string]$Relative)
  if ([IO.Path]::IsPathRooted($Relative)) {
    return $Relative
  }
  return (Join-Path $Root ($Relative -replace '/', '\'))
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$manifest = Join-Path $root '.agent-index\agent-index.yaml'
if (-not (Test-Path -LiteralPath $manifest)) {
  throw "Missing manifest: $manifest"
}

$lines = @(Get-Content -LiteralPath $manifest)
$errors = New-Object System.Collections.Generic.List[string]

foreach ($required in @('version:', 'project:', 'providers:', 'repos:', 'policies:')) {
  if (-not ($lines | Where-Object { $_ -match "^$([regex]::Escape($required))" })) {
    $errors.Add("Missing top-level section/value: $required")
  }
}

$repoPaths = @()
foreach ($line in $lines) {
  if ($line -match '^\s*-\s+path:\s*(.+?)\s*$') {
    $repoPaths += $Matches[1].Trim("'`"")
  }
}

if ($repoPaths.Count -eq 0) {
  $errors.Add('No repos configured.')
}

foreach ($repoPath in $repoPaths) {
  $full = Resolve-ProjectPath -Root $root -Relative $repoPath
  if (-not (Test-Path -LiteralPath $full)) {
    $errors.Add("Repo path missing: $repoPath")
  } elseif (-not (Test-Path -LiteralPath (Join-Path $full '.git'))) {
    $errors.Add("Repo path is not a git repo: $repoPath")
  }
}

foreach ($line in $lines) {
  if ($line -match '^\s*(wrapper|mcp):\s*(.+?)\s*$') {
    $relative = $Matches[2].Trim("'`"")
    $full = Resolve-ProjectPath -Root $root -Relative $relative
    if (-not (Test-Path -LiteralPath $full)) {
      $errors.Add("Configured path missing: $relative")
    }
  }
}

foreach ($line in $lines) {
  if ($line -match '^\s*(entry_skill|workspace_skill|lifecycle_skill|usage_skill):\s*(.+?)\s*$') {
    $skill = $Matches[2].Trim("'`"")
    $skillPath = Join-Path $root ".agents\skills\$skill\SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) {
      $errors.Add("Project skill missing: $skill")
    }
  }
}

if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_ }
  throw "Manifest validation failed with $($errors.Count) error(s)."
}

Write-Host "Manifest OK: $manifest"
Write-Host "Repos: $($repoPaths -join ', ')"
