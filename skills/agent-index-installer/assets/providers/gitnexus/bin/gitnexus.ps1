$ErrorActionPreference = "Stop"

$AgentIndexDir = Split-Path -Parent $PSScriptRoot
$ProjectRoot = Split-Path -Parent $AgentIndexDir
$env:GITNEXUS_HOME = Join-Path $AgentIndexDir "gitnexus-home"
New-Item -ItemType Directory -Force -Path $env:GITNEXUS_HOME | Out-Null
$env:npm_config_cache = Join-Path $AgentIndexDir "npm-cache"
New-Item -ItemType Directory -Force -Path $env:npm_config_cache | Out-Null
$env:XDG_CONFIG_HOME = Join-Path $AgentIndexDir "xdg-config"
New-Item -ItemType Directory -Force -Path $env:XDG_CONFIG_HOME | Out-Null
$ProjectGitIgnore = Join-Path $env:XDG_CONFIG_HOME "git\ignore"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ProjectGitIgnore) | Out-Null
if (-not (Test-Path -LiteralPath $ProjectGitIgnore)) {
  New-Item -ItemType File -Force -Path $ProjectGitIgnore | Out-Null
}
if (-not $env:NODE_NO_WARNINGS) {
  $env:NODE_NO_WARNINGS = "1"
}

function Get-ManifestRepoPaths([string]$Root) {
  $manifest = Join-Path $Root ".agent-index\agent-index.yaml"
  if (-not (Test-Path -LiteralPath $manifest)) {
    return @()
  }

  $repoPaths = @()
  $insideRepos = $false
  foreach ($line in Get-Content -LiteralPath $manifest) {
    if ($line -match "^repos:\s*(\[\])?\s*$") {
      $insideRepos = $true
      continue
    }
    if ($insideRepos -and $line -match "^[A-Za-z0-9_-]+:\s*") {
      break
    }
    if ($insideRepos -and $line -match "^\s*-\s+path:\s*(.+?)\s*$") {
      $repoPaths += $Matches[1].Trim("'`"")
    }
  }
  return @($repoPaths)
}

function Get-SafeGitDirs([string]$Root) {
  $dirs = @(Resolve-Path -LiteralPath $Root | ForEach-Object { $_.Path })
  $repoPaths = @(Get-ManifestRepoPaths -Root $Root)
  if ($repoPaths.Count -gt 0) {
    foreach ($repoPath in $repoPaths) {
      $candidate = if ([IO.Path]::IsPathRooted($repoPath)) {
        $repoPath
      } else {
        Join-Path $Root ($repoPath -replace "/", "\")
      }
      if (Test-Path -LiteralPath (Join-Path $candidate ".git")) {
        $dirs += (Resolve-Path -LiteralPath $candidate).Path
      }
    }
  } else {
    $dirs += Get-ChildItem -LiteralPath $Root -Force -Directory |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName ".git") } |
      ForEach-Object { $_.FullName }
  }
  return @($dirs | Sort-Object -Unique)
}

$SafeGitDirs = Get-SafeGitDirs -Root $ProjectRoot
$GitConfigEntries = @()
foreach ($safeGitDir in $SafeGitDirs) {
  $GitConfigEntries += [pscustomobject]@{
    Key = "safe.directory"
    Value = ($safeGitDir -replace "\\", "/")
  }
}
$GitConfigEntries += [pscustomobject]@{
  Key = "core.excludesFile"
  Value = ($ProjectGitIgnore -replace "\\", "/")
}
$env:GIT_CONFIG_COUNT = [string]$GitConfigEntries.Count
for ($i = 0; $i -lt $GitConfigEntries.Count; $i++) {
  Set-Item -Path "Env:GIT_CONFIG_KEY_$i" -Value $GitConfigEntries[$i].Key
  Set-Item -Path "Env:GIT_CONFIG_VALUE_$i" -Value $GitConfigEntries[$i].Value
}

function Resolve-AnalyzeRepoPath([object[]]$RawArgs) {
  if ($RawArgs.Count -eq 0 -or [string]$RawArgs[0] -ne "analyze") {
    return $null
  }
  if ($RawArgs -contains "--help" -or $RawArgs -contains "-h") {
    return $null
  }

  $optionsWithRequiredValues = @(
    "--name",
    "--max-file-size",
    "--worker-timeout",
    "--embedding-threads",
    "--embedding-batch-size",
    "--embedding-sub-batch-size",
    "--embedding-device"
  )

  for ($i = 1; $i -lt $RawArgs.Count; $i++) {
    $current = [string]$RawArgs[$i]
    if ($optionsWithRequiredValues -contains $current) {
      $i++
      continue
    }
    if ($current -eq "--embeddings") {
      if (($i + 1) -lt $RawArgs.Count -and [string]$RawArgs[$i + 1] -match "^\d+$") {
        $i++
      }
      continue
    }
    if ($current.StartsWith("-")) {
      continue
    }

    $candidate = $current
    if (-not [IO.Path]::IsPathRooted($candidate)) {
      $candidate = Join-Path $ProjectRoot $candidate
    }
    return (Resolve-Path -LiteralPath $candidate).Path
  }

  return (Resolve-Path -LiteralPath $ProjectRoot).Path
}

function Test-GitNexusSupportsSkipSkills([string]$NpxPath, [string]$Version) {
  $help = & $NpxPath -y "gitnexus@$Version" analyze --help 2>$null
  return (($help -join "`n") -match "--skip-skills")
}

function Get-SkillStatus([string]$RepoPath) {
  if (-not $RepoPath -or -not (Test-Path -LiteralPath (Join-Path $RepoPath ".git"))) {
    return $null
  }
  return (& git -C $RepoPath status --porcelain -- .claude/skills/gitnexus 2>$null) -join "`n"
}

function Restore-TrackedSkillsIfCleanBefore([string]$RepoPath, [string]$StatusBefore) {
  if (-not $RepoPath -or -not (Test-Path -LiteralPath (Join-Path $RepoPath ".git"))) {
    return
  }

  $tracked = (& git -C $RepoPath ls-files -- .claude/skills/gitnexus 2>$null) -join "`n"
  if (-not $tracked) {
    return
  }

  $statusAfter = Get-SkillStatus $RepoPath
  if (-not $statusAfter) {
    return
  }

  if ($StatusBefore) {
    Write-Warning "Leaving pre-existing tracked .claude/skills/gitnexus changes untouched in $RepoPath"
    return
  }

  & git -C $RepoPath restore -- .claude/skills/gitnexus
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to restore tracked GitNexus skills in $RepoPath"
  }
  Write-Host "[restored tracked] $RepoPath\.claude\skills\gitnexus"
}

$GitNexusVersion = if ($env:GITNEXUS_VERSION) { $env:GITNEXUS_VERSION } else { "1.6.4" }
$Npx = Get-Command npx.cmd -ErrorAction SilentlyContinue
if (-not $Npx) {
  $Npx = Get-Command npx -ErrorAction Stop
}

$RawArgs = @($args)
$AnalyzeRepoPath = Resolve-AnalyzeRepoPath $RawArgs
$SkillStatusBefore = Get-SkillStatus $AnalyzeRepoPath
$ShouldSuppressRepoSkills = $AnalyzeRepoPath -and -not ($RawArgs -contains "--skills")
if ($ShouldSuppressRepoSkills -and (Test-GitNexusSupportsSkipSkills $Npx.Source $GitNexusVersion)) {
  if (-not ($RawArgs -contains "--skip-skills")) {
    $RawArgs += "--skip-skills"
  }
}

Push-Location $ProjectRoot
try {
  & $Npx.Source -y "gitnexus@$GitNexusVersion" @RawArgs
  $exitCode = $LASTEXITCODE
  if ($exitCode -eq 0 -and $ShouldSuppressRepoSkills) {
    & (Join-Path $PSScriptRoot "gitnexus-clean-repo-injections.ps1") -Repo $AnalyzeRepoPath
    Restore-TrackedSkillsIfCleanBefore $AnalyzeRepoPath $SkillStatusBefore
  }
  exit $exitCode
} finally {
  Pop-Location
}
