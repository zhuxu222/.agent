param([string]$ProjectRoot = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'validate-codegraph.ps1') -ProjectRoot $ProjectRoot
exit $LASTEXITCODE
