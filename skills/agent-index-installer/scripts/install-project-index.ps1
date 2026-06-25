param(
  [string]$ProjectRoot = (Get-Location).Path,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Copy-DirectoryChildren {
  param([string]$Source, [string]$Destination, [switch]$Overwrite)

  if (-not (Test-Path -LiteralPath $Source)) {
    return
  }
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null
  foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
    $target = Join-Path $Destination $item.Name
    if ($item.PSIsContainer) {
      if ((Test-Path -LiteralPath $target) -and $Overwrite) {
        Remove-Item -LiteralPath $target -Recurse -Force
      }
      if (-not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $item.FullName -Destination $target -Recurse -Force
      }
    } else {
      if ($Overwrite -or -not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force
      }
    }
  }
}

function Write-IfMissing {
  param([string]$Path, [string]$Content)
  if (-not (Test-Path -LiteralPath $Path)) {
    $parent = Split-Path -Parent $Path
    if ($parent) {
      New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
  }
}

function Read-AssetTemplate {
  param([string]$RelativePath)
  $path = Join-Path $assets $RelativePath
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing installer template: $path"
  }
  return Get-Content -LiteralPath $path -Raw
}

function Repair-KnownAgentInstructionsEscapes {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return
  }

  $content = Get-Content -LiteralPath $Path -Raw
  if (($content -notlike '# Agent Instructions*') -or ($content -notmatch "bare\s+`r?`npx gitnexus")) {
    return
  }

  $fixed = Read-AssetTemplate -RelativePath 'common\AGENTS.md.template'
  Set-Content -LiteralPath $Path -Value $fixed -Encoding UTF8
}

function ConvertTo-StableName {
  param([string]$Value)
  $name = $Value.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
  return $name.Trim('-')
}

$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$skillRoot = Split-Path -Parent $PSScriptRoot
$assets = Join-Path $skillRoot 'assets'
$projectName = ConvertTo-StableName (Split-Path -Leaf $root)

$projectSkills = Join-Path $root '.agents\skills'
$binDir = Join-Path $root '.agent-index\bin'
$gitnexusHome = Join-Path $root '.agent-index\gitnexus-home'
New-Item -ItemType Directory -Force -Path $projectSkills, $binDir, $gitnexusHome | Out-Null

Copy-DirectoryChildren -Source (Join-Path $assets 'router\skills') -Destination $projectSkills -Overwrite:$Force
Copy-DirectoryChildren -Source (Join-Path $assets 'workspace\skills') -Destination $projectSkills -Overwrite:$Force
Copy-DirectoryChildren -Source (Join-Path $assets 'providers\codegraph\skills') -Destination $projectSkills -Overwrite:$Force
Copy-DirectoryChildren -Source (Join-Path $assets 'providers\gitnexus\skills') -Destination $projectSkills -Overwrite:$Force
Copy-DirectoryChildren -Source (Join-Path $assets 'providers\codegraph\bin') -Destination $binDir -Overwrite:$Force
Copy-DirectoryChildren -Source (Join-Path $assets 'providers\gitnexus\bin') -Destination $binDir -Overwrite:$Force

$manifest = (Read-AssetTemplate -RelativePath 'common\agent-index.yaml.template').Replace('<project-name>', $projectName)
Write-IfMissing -Path (Join-Path $root '.agent-index\agent-index.yaml') -Content $manifest

$projectRootForConfig = $root -replace '\\','/'
$config = (Read-AssetTemplate -RelativePath 'common\config.toml.template').Replace('<project-root>', $projectRootForConfig)
Write-IfMissing -Path (Join-Path $root '.codex\config.toml') -Content $config

$agentIndexIgnore = Read-AssetTemplate -RelativePath 'common\agent-index.gitignore.template'
Write-IfMissing -Path (Join-Path $root '.agent-index\.gitignore') -Content $agentIndexIgnore

$gitnexusHomeIgnore = Read-AssetTemplate -RelativePath 'common\gitnexus-home.gitignore.template'
Write-IfMissing -Path (Join-Path $root '.agent-index\gitnexus-home\.gitignore') -Content $gitnexusHomeIgnore

$agents = Read-AssetTemplate -RelativePath 'common\AGENTS.md.template'
$agentsPath = Join-Path $root 'AGENTS.md'
Write-IfMissing -Path $agentsPath -Content $agents
Repair-KnownAgentInstructionsEscapes -Path $agentsPath

Write-Host "Installed project index skills and tools under $root"
Write-Host "Next: run .\.agents\skills\agent-index-workspace\scripts\initialize-workspace.ps1, then .\.agents\skills\agent-index-lifecycle\scripts\invoke-agent-index-lifecycle.ps1 -Mode Build"
