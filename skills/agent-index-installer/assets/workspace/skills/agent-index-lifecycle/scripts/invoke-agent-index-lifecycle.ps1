param(
  [ValidateSet('Build', 'Refresh', 'Validate', 'Repair', 'Status')]
  [string]$Mode = 'Validate',
  [string]$ProjectRoot = (Get-Location).Path,
  [string[]]$Provider = @()
)

$ErrorActionPreference = 'Stop'

function Get-EnabledProviders {
  param([string]$ManifestPath)

  $providers = @()
  $insideProviders = $false
  $current = $null

  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^providers:\s*$') {
      $insideProviders = $true
      continue
    }
    if ($insideProviders -and $line -match '^[A-Za-z0-9_-]+:\s*') {
      break
    }
    if (-not $insideProviders) {
      continue
    }
    if ($line -match '^\s{2}([A-Za-z0-9_-]+):\s*$') {
      if ($null -ne $current) {
        $providers += $current
      }
      $current = [ordered]@{ Name = $Matches[1]; Enabled = $true; LifecycleSkill = $null }
      continue
    }
    if ($null -eq $current) {
      continue
    }
    if ($line -match '^\s{4}enabled:\s*(true|false)\s*$') {
      $current.Enabled = [bool]::Parse($Matches[1])
      continue
    }
    if ($line -match '^\s{4}lifecycle_skill:\s*(.+?)\s*$') {
      $current.LifecycleSkill = $Matches[1].Trim("'`"")
      continue
    }
  }

  if ($null -ne $current) {
    $providers += $current
  }

  return @($providers | Where-Object { $_['Enabled'] -and $_['LifecycleSkill'] })
}

function Invoke-ProviderScript {
  param(
    [string]$Root,
    [object]$ProviderEntry,
    [string]$ScriptName
  )

  $providerName = [string]$ProviderEntry['Name']
  $lifecycleSkill = [string]$ProviderEntry['LifecycleSkill']
  $script = Join-Path $Root ".agents\skills\$lifecycleSkill\scripts\$ScriptName.ps1"
  if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing provider script for ${providerName}: $script"
  }

  Write-Host "[$providerName] $ScriptName"
  & $script -ProjectRoot $Root
  if ($LASTEXITCODE -ne 0) {
    throw "Provider $providerName failed in $ScriptName with exit code $LASTEXITCODE"
  }
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$manifest = Join-Path $root '.agent-index\agent-index.yaml'
if (-not (Test-Path -LiteralPath $manifest)) {
  throw "Missing manifest: $manifest"
}

$providers = @(Get-EnabledProviders -ManifestPath $manifest)
if ($Provider.Count -gt 0) {
  $providers = @($providers | Where-Object { $Provider -contains $_['Name'] })
}
if ($providers.Count -eq 0) {
  throw "No enabled providers selected."
}

$ensureExcludes = Join-Path $root '.agents\skills\agent-index-workspace\scripts\ensure-repo-excludes.ps1'
if (Test-Path -LiteralPath $ensureExcludes) {
  & $ensureExcludes -ProjectRoot $root
}

$scriptName = switch ($Mode) {
  'Build' { 'build' }
  'Refresh' { 'refresh' }
  'Validate' { 'validate' }
  'Repair' { 'repair' }
  'Status' { 'status' }
}

$failures = New-Object System.Collections.Generic.List[string]
foreach ($providerEntry in $providers) {
  try {
    Invoke-ProviderScript -Root $root -ProviderEntry $providerEntry -ScriptName $scriptName
    if ($Mode -in @('Build', 'Refresh', 'Repair')) {
      Invoke-ProviderScript -Root $root -ProviderEntry $providerEntry -ScriptName 'validate'
    }
  } catch {
    $failures.Add("$($providerEntry['Name']): $($_.Exception.Message)")
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  throw "Index lifecycle $Mode failed for $($failures.Count) provider(s)."
}

Write-Host "Index lifecycle $Mode completed for: $(@($providers | ForEach-Object { $_['Name'] }) -join ', ')"
