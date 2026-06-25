param(
  [string]$ProjectRoot = (Get-Location).Path,
  [switch]$StopProjectMcp,
  [switch]$SkipMcpGuard,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Resolve-StrictPath {
  param([string]$Path)
  return (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
}

function Test-PathUnder {
  param([string]$Child, [string]$Parent)

  $normalizedChild = $Child.TrimEnd('\', '/')
  $normalizedParent = $Parent.TrimEnd('\', '/')
  if ($normalizedChild.Equals($normalizedParent, [StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }

  $prefix = $normalizedParent + [IO.Path]::DirectorySeparatorChar
  return $normalizedChild.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Get-ManifestRepoPaths {
  param([string]$ManifestPath)

  $paths = @()
  if (-not (Test-Path -LiteralPath $ManifestPath)) {
    return @($paths)
  }

  foreach ($line in Get-Content -LiteralPath $ManifestPath) {
    if ($line -match '^\s*-\s+path:\s*(.+?)\s*$') {
      $paths += $Matches[1].Trim("'`"")
    }
  }
  return @($paths)
}

function Resolve-ProjectPath {
  param([string]$Root, [string]$Relative)

  if ([IO.Path]::IsPathRooted($Relative)) {
    return Resolve-StrictPath $Relative
  }

  return Resolve-StrictPath (Join-Path $Root ($Relative -replace '/', '\'))
}

function Get-DiscoveredGitRepos {
  param([string]$Root)

  $discover = Join-Path $Root '.agents\skills\agent-index-workspace\scripts\discover-repos.ps1'
  if (-not (Test-Path -LiteralPath $discover)) {
    return @()
  }

  $repoJson = (& $discover -ProjectRoot $Root | Out-String).Trim()
  if (-not $repoJson) {
    return @()
  }

  return @($repoJson | ConvertFrom-Json | ForEach-Object { $_.fullPath })
}

function Get-ProjectMcpProcessTree {
  param([string]$Root)

  try {
    $all = @(Get-CimInstance Win32_Process)
  } catch {
    throw "Unable to inspect process command lines for MCP guard. Run with sufficient permissions or pass -SkipMcpGuard. $($_.Exception.Message)"
  }

  $rootForward = ($Root -replace '\\', '/')
  $rootBackslash = ($Root -replace '/', '\')
  $binForward = [regex]::Escape("$rootForward/.agent-index/bin")
  $binBackslash = [regex]::Escape("$rootBackslash\.agent-index\bin")

  $rootIds = @($all | Where-Object {
    $_.CommandLine -and
    (($_.CommandLine -match $binForward) -or ($_.CommandLine -match $binBackslash)) -and
    ($_.CommandLine -match 'codegraph-mcp\.ps1|gitnexus-mcp\.ps1')
  } | ForEach-Object { [int]$_.ProcessId })

  $ids = [System.Collections.Generic.HashSet[int]]::new()
  foreach ($id in $rootIds) {
    [void]$ids.Add($id)
  }

  $changed = $true
  while ($changed) {
    $changed = $false
    foreach ($process in $all) {
      if ($ids.Contains([int]$process.ParentProcessId) -and -not $ids.Contains([int]$process.ProcessId)) {
        [void]$ids.Add([int]$process.ProcessId)
        $changed = $true
      }
    }
  }

  return @($all | Where-Object { $ids.Contains([int]$_.ProcessId) })
}

function Assert-ProjectMcpStopped {
  param(
    [string]$Root,
    [switch]$Stop
  )

  $mcpProcesses = @(Get-ProjectMcpProcessTree -Root $Root)
  if ($mcpProcesses.Count -eq 0) {
    return
  }

  if (-not $Stop) {
    Write-Host 'Project MCP processes are running:'
    foreach ($process in $mcpProcesses | Sort-Object ProcessId) {
      Write-Host "  PID=$($process.ProcessId) NAME=$($process.Name) CMD=$($process.CommandLine)"
    }
    throw 'Refusing to clean index artifacts while project MCP processes are running. Re-run with -StopProjectMcp to stop only this project MCP process tree, then restart the Codex session before MCP tool verification.'
  }

  foreach ($process in @($mcpProcesses | Sort-Object ProcessId -Descending)) {
    $live = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
    if ($live) {
      Write-Host "Stopping project MCP process: PID=$($process.ProcessId) NAME=$($live.ProcessName)"
      Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }

  Start-Sleep -Seconds 1
  Write-Host 'Stopped project MCP process tree. Restart the Codex session before MCP tool verification.'
}

function Remove-PathIfExists {
  param(
    [string]$Path,
    [string]$Root,
    [switch]$DryRun
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $resolved = Resolve-StrictPath $Path
  if (-not (Test-PathUnder -Child $resolved -Parent $Root)) {
    throw "Refusing to remove outside project root: $resolved"
  }

  if ($DryRun) {
    Write-Host "[dry-run remove] $resolved"
    return
  }

  Remove-Item -LiteralPath $resolved -Recurse -Force
  Write-Host "[removed] $resolved"
}

$root = Resolve-StrictPath $ProjectRoot
$manifest = Join-Path $root '.agent-index\agent-index.yaml'

if (-not $SkipMcpGuard) {
  Assert-ProjectMcpStopped -Root $root -Stop:$StopProjectMcp
}

$repoPaths = @(Get-ManifestRepoPaths -ManifestPath $manifest)
if ($repoPaths.Count -gt 0) {
  $repos = @($repoPaths | ForEach-Object { Resolve-ProjectPath -Root $root -Relative $_ })
} else {
  $repos = Get-DiscoveredGitRepos -Root $root
}

foreach ($repo in $repos) {
  if (-not (Test-PathUnder -Child $repo -Parent $root)) {
    throw "Refusing to clean repo outside project root: $repo"
  }

  foreach ($relative in @('.codegraph', '.gitnexus', '.understand-anything')) {
    Remove-PathIfExists -Path (Join-Path $repo $relative) -Root $root -DryRun:$DryRun
  }
}

foreach ($relative in @(
  '.agent-index\gitnexus-home\registry.json',
  '.agent-index\npm-cache'
)) {
  Remove-PathIfExists -Path (Join-Path $root $relative) -Root $root -DryRun:$DryRun
}

$contracts = Join-Path $root '.agent-index\gitnexus-home\groups'
if (Test-Path -LiteralPath $contracts) {
  Get-ChildItem -LiteralPath $contracts -Recurse -Force -File -Filter 'contracts.json' |
    ForEach-Object { Remove-PathIfExists -Path $_.FullName -Root $root -DryRun:$DryRun }
}

$cleanup = Join-Path $root '.agent-index\bin\gitnexus-clean-repo-injections.ps1'
if ((-not $DryRun) -and (Test-Path -LiteralPath $cleanup)) {
  & $cleanup
  if ($LASTEXITCODE -ne 0) {
    throw "GitNexus repo injection cleanup failed with exit code $LASTEXITCODE"
  }
}

Write-Host "Project index artifact cleanup completed: $root"
