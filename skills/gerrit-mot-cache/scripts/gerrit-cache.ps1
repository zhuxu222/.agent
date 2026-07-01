#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('clone', 'update-cache', 'pull', 'fetch', 'validate', 'repair', 'cache-path', 'push-review')]
    [string]$Command,

    [Parameter(Position = 1)]
    [string]$Target,

    [Parameter(Position = 2)]
    [string]$Worktree,

    [string]$CacheRoot,

    [string]$GerritHost = 'gerrit.mot.com',

    [string]$MainBranch = 'master',

    [switch]$NoFsck
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pythonScript = Join-Path $scriptDir 'gerrit_cache.py'

$python = $env:PYTHON
if ([string]::IsNullOrWhiteSpace($python)) {
    $python = 'python'
}

$arguments = @()
if (-not [string]::IsNullOrWhiteSpace($CacheRoot)) {
    $arguments += @('--cache-root', $CacheRoot)
}
if ($GerritHost -ne 'gerrit.mot.com') {
    $arguments += @('--gerrit-host', $GerritHost)
}
if ($MainBranch -ne 'master') {
    $arguments += @('--main-branch', $MainBranch)
}
if ($NoFsck) {
    $arguments += '--no-fsck'
}
$arguments += $Command
if (-not [string]::IsNullOrWhiteSpace($Target)) {
    $arguments += $Target
}
if (-not [string]::IsNullOrWhiteSpace($Worktree)) {
    $arguments += $Worktree
}

& $python $pythonScript @arguments
exit $LASTEXITCODE
