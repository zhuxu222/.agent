param(
  [string]$ProjectRoot = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'install-project-index.ps1') -ProjectRoot $ProjectRoot -Force
exit $LASTEXITCODE
