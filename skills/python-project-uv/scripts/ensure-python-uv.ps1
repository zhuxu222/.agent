param(
  [string]$ProjectRoot = (Get-Location).Path,
  [string[]]$Packages = @(),
  [string]$Python = '',
  [switch]$Recreate
)

$ErrorActionPreference = 'Stop'

function Invoke-Checked {
  param(
    [string]$Command,
    [string[]]$Arguments
  )

  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
  }
}

$uv = Get-Command uv -ErrorAction SilentlyContinue
if (-not $uv) {
  throw 'uv is required by the user-level Python policy, but uv was not found on PATH.'
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$venv = Join-Path $root '.venv'
$venvPython = Join-Path $venv 'Scripts\python.exe'
$uvCache = Join-Path $root '.uv-cache'
New-Item -ItemType Directory -Force -Path $uvCache | Out-Null
$env:UV_CACHE_DIR = $uvCache

if ($Recreate -and (Test-Path -LiteralPath $venv)) {
  $args = @('venv', '--clear')
  if ($Python) {
    $args += @('--python', $Python)
  }
  $args += @($venv)
  Invoke-Checked -Command $uv.Source -Arguments $args
} elseif (-not (Test-Path -LiteralPath $venvPython)) {
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  $args = @('venv')
  if ($Python) {
    $args += @('--python', $Python)
  }
  $args += @($venv)
  Invoke-Checked -Command $uv.Source -Arguments $args
}

if (-not (Test-Path -LiteralPath $venvPython)) {
  throw "uv did not create the expected Python executable: $venvPython"
}

Invoke-Checked -Command $uv.Source -Arguments @('pip', 'list', '--python', $venvPython)

foreach ($package in $Packages) {
  Invoke-Checked -Command $uv.Source -Arguments @('pip', 'install', '--python', $venvPython, $package)
}

Write-Output $venvPython
