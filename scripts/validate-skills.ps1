param(
  [string]$SkillsRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills')
)

$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]
$root = (Resolve-Path -LiteralPath $SkillsRoot).Path.TrimEnd('\', '/')

function Add-Error([string]$Message) {
  $script:errors.Add($Message) | Out-Null
}

function Test-DirectoryLinkTargets {
  Get-ChildItem -LiteralPath $root -Force | Where-Object { $_.PSIsContainer -and $_.LinkType } | ForEach-Object {
    $target = @($_.Target | Select-Object -First 1)[0]
    if (-not $target -or -not (Test-Path -LiteralPath $target)) {
      Add-Error "Broken directory link: $($_.FullName) -> $target"
    }
  }
}

function Test-SkillFrontmatter {
  Get-ChildItem -LiteralPath $root -Recurse -Filter 'SKILL.md' -File | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw
    if ($content -notmatch '(?s)^---\s*\r?\n(.+?)\r?\n---\s*\r?\n') {
      Add-Error "Missing YAML frontmatter: $($_.FullName)"
      return
    }
    $frontmatter = $Matches[1]
    if ($frontmatter -notmatch '(?m)^name:\s*[a-z0-9][a-z0-9-]*\s*$') {
      Add-Error "Missing or invalid skill name: $($_.FullName)"
    }
    if ($frontmatter -notmatch '(?m)^description:\s*.+$') {
      Add-Error "Missing description: $($_.FullName)"
    }
  }
}

function Test-OpenAIYaml {
  Get-ChildItem -LiteralPath $root -Recurse -Filter 'openai.yaml' -File | ForEach-Object {
    $content = Get-Content -LiteralPath $_.FullName -Raw
    if ($content -notmatch '(?m)^interface:\s*$') {
      Add-Error "openai.yaml missing interface block: $($_.FullName)"
    }
    foreach ($field in @('display_name', 'short_description', 'default_prompt')) {
      $pattern = '(?m)^\s{2}' + [regex]::Escape($field) + ': ".+"\s*$'
      if ($content -notmatch $pattern) {
        Add-Error ("openai.yaml missing quoted interface.{0}: {1}" -f $field, $_.FullName)
      }
    }
    $skillDir = Split-Path -Parent (Split-Path -Parent $_.FullName)
    $skillName = Split-Path -Leaf $skillDir
    $skillToken = '$' + $skillName
    if ($content -notmatch [regex]::Escape($skillToken)) {
      Add-Error ("openai.yaml default_prompt should mention {0}: {1}" -f $skillToken, $_.FullName)
    }
  }
}

function Test-PowerShellSyntax {
  Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($parseError in $parseErrors) {
      Add-Error "PowerShell parse error: $($_.FullName):$($parseError.Extent.StartLineNumber): $($parseError.Message)"
    }
  }
}

Test-DirectoryLinkTargets
Test-SkillFrontmatter
Test-OpenAIYaml
Test-PowerShellSyntax

if ($errors.Count -gt 0) {
  $errors | ForEach-Object { Write-Error $_ }
  throw "Skill validation failed with $($errors.Count) error(s)."
}

Write-Host "Skill validation OK: $root"
