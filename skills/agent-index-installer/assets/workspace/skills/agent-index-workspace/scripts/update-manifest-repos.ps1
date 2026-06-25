param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function ConvertTo-StableName {
  param([string]$Value)
  $name = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
  return $name.Trim('-')
}

function Get-ProjectName {
  param([string]$Root, [string[]]$Lines)
  foreach ($line in $Lines) {
    if ($line -match '^\s*project:\s*(.+?)\s*$') {
      return (ConvertTo-StableName $Matches[1].Trim("'`""))
    }
  }
  return (ConvertTo-StableName (Split-Path -Leaf $Root))
}

function Get-GitNexusGroup {
  param([string[]]$Lines, [string]$DefaultGroup)
  foreach ($line in $Lines) {
    if ($line -match '^\s*group:\s*(.+?)\s*$') {
      return $Matches[1].Trim("'`"")
    }
  }
  return $DefaultGroup
}

function ConvertTo-GroupPath {
  param([string]$Value)
  $path = ($Value -replace '\\', '/').Trim('/')
  return $path.ToLowerInvariant()
}

function Write-GitNexusGroup {
  param(
    [string]$Root,
    [string]$GroupName,
    [object[]]$Repos
  )

  if (-not $GroupName) {
    return
  }

  $groupDir = Join-Path $Root ".agent-index\gitnexus-home\groups\$GroupName"
  New-Item -ItemType Directory -Force -Path $groupDir | Out-Null
  $groupPath = Join-Path $groupDir 'group.yaml'

  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('version: 1')
  $lines.Add("name: $GroupName")
  $lines.Add("description: ''")
  $lines.Add('repos:')
  foreach ($repo in $Repos) {
    $groupRepoPath = ConvertTo-GroupPath $repo.path
    $lines.Add("  ${groupRepoPath}: $($repo.name)")
  }
  $lines.Add('links: []')
  $lines.Add('packages: {}')
  $lines.Add('detect:')
  $lines.Add('  http: true')
  $lines.Add('  grpc: true')
  $lines.Add('  thrift: true')
  $lines.Add('  topics: true')
  $lines.Add('  shared_libs: true')
  $lines.Add('  embedding_fallback: true')
  $lines.Add('  includes: false')
  $lines.Add('  workspace_deps: false')
  $lines.Add('matching:')
  $lines.Add('  bm25_threshold: 0.7')
  $lines.Add('  embedding_threshold: 0.65')
  $lines.Add('  max_candidates_per_step: 3')
  $lines.Add('  exclude_links_paths: []')
  $lines.Add('  exclude_links_param_only_paths: false')

  Set-Content -LiteralPath $groupPath -Value $lines -Encoding UTF8
  Write-Host "Updated GitNexus group: $groupPath"
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$manifest = Join-Path $root '.agent-index\agent-index.yaml'
if (-not (Test-Path -LiteralPath $manifest)) {
  throw "Missing manifest: $manifest"
}

$lines = @(Get-Content -LiteralPath $manifest)
$projectName = Get-ProjectName -Root $root -Lines $lines
$gitnexusGroup = Get-GitNexusGroup -Lines $lines -DefaultGroup $projectName
$discover = Join-Path $PSScriptRoot 'discover-repos.ps1'
$repoJson = (& $discover -ProjectRoot $root | Out-String).Trim()
$repos = if ($repoJson) { @($repoJson | ConvertFrom-Json) } else { @() }

if ($repos.Count -eq 0) {
  throw "No git repos found from configured workspace roots under $root"
}

$repoBlock = New-Object System.Collections.Generic.List[string]
$repoBlock.Add('repos:')
foreach ($repo in $repos) {
  $repoBlock.Add("  - path: $($repo.path)")
  $repoBlock.Add("    name: $($repo.name)")
}

$repoIndex = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^repos:\s*(\[\])?\s*$') {
    $repoIndex = $i
    break
  }
}

if ($repoIndex -lt 0) {
  $newLines = @($lines + '' + $repoBlock)
} else {
  $endIndex = $lines.Count
  for ($i = $repoIndex + 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^[A-Za-z0-9_-]+:\s*') {
      $endIndex = $i
      break
    }
  }
  $newLines = @()
  if ($repoIndex -gt 0) {
    $newLines += $lines[0..($repoIndex - 1)]
  }
  $newLines += $repoBlock
  if ($endIndex -lt $lines.Count) {
    $newLines += $lines[$endIndex..($lines.Count - 1)]
  }
}

Set-Content -LiteralPath $manifest -Value $newLines -Encoding UTF8
Write-GitNexusGroup -Root $root -GroupName $gitnexusGroup -Repos $repos
& (Join-Path $PSScriptRoot 'ensure-repo-excludes.ps1') -ProjectRoot $root
Write-Host "Updated manifest repos: $manifest"
foreach ($line in $repoBlock) {
  Write-Host $line
}
