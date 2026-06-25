param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path

$updateManifest = Join-Path $PSScriptRoot 'update-manifest-repos.ps1'
$ensureExcludes = Join-Path $PSScriptRoot 'ensure-repo-excludes.ps1'
$validateManifest = Join-Path $PSScriptRoot 'validate-manifest.ps1'

foreach ($script in @($updateManifest, $ensureExcludes, $validateManifest)) {
  if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing workspace script: $script"
  }
}

Write-Host "Initialize workspace: update manifest repos"
& $updateManifest -ProjectRoot $root

Write-Host "Initialize workspace: ensure repo excludes"
& $ensureExcludes -ProjectRoot $root

Write-Host "Initialize workspace: validate manifest"
& $validateManifest -ProjectRoot $root

Write-Host "Workspace initialization completed: $root"
