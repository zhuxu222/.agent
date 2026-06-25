param([string]$ProjectRoot = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'index-codegraph.ps1') -ProjectRoot $ProjectRoot -Rebuild
exit $LASTEXITCODE
