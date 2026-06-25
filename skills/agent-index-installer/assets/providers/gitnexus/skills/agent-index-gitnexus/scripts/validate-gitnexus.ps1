param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

function Get-ManifestGroup {
  param([string]$ManifestPath)

  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^\s*group:\s*(.+?)\s*$') {
      return $Matches[1].Trim("'`"")
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

Write-Host 'GitNexus indexed repos:'
& $wrapper list
if ($LASTEXITCODE -ne 0) {
  throw "GitNexus list failed with exit code $LASTEXITCODE"
}

$group = Get-ManifestGroup -ManifestPath $manifest
if ($group) {
  Write-Host "GitNexus group status: $group"
  & $wrapper group status $group
  if ($LASTEXITCODE -ne 0) {
    throw "GitNexus group status failed for $group with exit code $LASTEXITCODE"
  }
}

if (Test-Path -LiteralPath $cleanup) {
  Write-Host 'GitNexus repo injection cleanup dry run:'
  & $cleanup -DryRun
}
