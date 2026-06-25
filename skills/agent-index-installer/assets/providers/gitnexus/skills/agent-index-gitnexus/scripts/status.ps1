param([string]$ProjectRoot = (Get-Location).Path)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'validate-gitnexus.ps1') -ProjectRoot $ProjectRoot
exit $LASTEXITCODE
