param([string]$ProjectRoot = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'index-gitnexus.ps1') -ProjectRoot $ProjectRoot
exit $LASTEXITCODE
