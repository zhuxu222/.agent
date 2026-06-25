param([string]$ProjectRoot = (Get-Location).Path)

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

if (Test-Path -LiteralPath $cleanup) {
  & $cleanup
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$group = Get-ManifestGroup -ManifestPath $manifest
if ($group -and (Test-Path -LiteralPath $wrapper)) {
  & $wrapper group sync $group --skip-embeddings
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

& (Join-Path $PSScriptRoot 'validate-gitnexus.ps1') -ProjectRoot $root
exit $LASTEXITCODE
