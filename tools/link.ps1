<#
.SYNOPSIS
    Point the WoW: Forever client at this working copy, so testing a branch is
    just pulling it and typing /reload.

.DESCRIPTION
    Creates a junction at Interface\AddOns\Blackthornes_Farmer that points at
    this repository folder. The client then loads the addon straight out of
    your checkout: switch branches in GitHub Desktop, type /reload in game, and
    you are running that branch. No copying, no deploy step.

    Run this once per machine. It is a junction, not a symlink, so it does not
    need an elevated prompt.

    Two things /reload will NOT pick up, because the client only reads them at
    startup: a file that was added or removed, and any change to the .toc.
    After pulling a branch that adds a file, restart the client once.

.PARAMETER GamePath
    Path to the client flavor folder. Defaults to the detected Forever beta.

.PARAMETER Force
    Replace whatever is already at the target path. A real folder is renamed
    out of the way rather than deleted.

.EXAMPLE
    .\tools\link.ps1
#>

[CmdletBinding()]
param(
    [string]$GamePath = 'D:\Blizzard\World of Warcraft\_forever_',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$AddonName = 'Blackthornes_Farmer'

# The repo root, one level up from tools\.
$SourceRoot = Split-Path $PSScriptRoot -Parent
$AddOnsRoot = Join-Path $GamePath 'Interface\AddOns'
$TargetRoot = Join-Path $AddOnsRoot $AddonName

if (-not (Test-Path $GamePath)) {
    throw "Game path not found: $GamePath  (pass -GamePath if the client lives elsewhere)"
}

# The addon folder name has to match the .toc file name or the client ignores
# the whole folder without saying anything.
$toc = Join-Path $SourceRoot "$AddonName.toc"
if (-not (Test-Path $toc)) {
    throw "Expected $AddonName.toc in $SourceRoot. The folder name and the .toc name must match."
}

if (-not (Test-Path $AddOnsRoot)) {
    New-Item -ItemType Directory -Path $AddOnsRoot -Force | Out-Null
}

$existing = Get-Item $TargetRoot -Force -ErrorAction SilentlyContinue

if ($existing) {
    $isLink = $existing.Attributes -band [IO.FileAttributes]::ReparsePoint

    if ($isLink) {
        Write-Host "Replacing the existing link at $TargetRoot" -ForegroundColor Cyan
        # Removing a junction removes the link, not what it points at.
        [IO.Directory]::Delete($TargetRoot)
    }
    elseif ($Force) {
        # A real folder here is a previously deployed copy. Rename rather than
        # delete: if it turns out to hold something you wanted, it is still there.
        $backup = "$TargetRoot.backup-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Write-Host "Moving the existing folder to $backup" -ForegroundColor Yellow
        Move-Item $TargetRoot $backup
    }
    else {
        Write-Host ''
        Write-Host "$TargetRoot already exists and is a real folder." -ForegroundColor Yellow
        Write-Host 'It is probably a copy from deploy.ps1. Re-run with -Force to' -ForegroundColor Yellow
        Write-Host 'move it aside and link this working copy instead.' -ForegroundColor Yellow
        exit 1
    }
}

New-Item -ItemType Junction -Path $TargetRoot -Value $SourceRoot | Out-Null

Write-Host ''
Write-Host "Linked $TargetRoot" -ForegroundColor Green
Write-Host "     -> $SourceRoot" -ForegroundColor Green
Write-Host ''
Write-Host 'From now on: pull a branch in GitHub Desktop, then /reload in game.' -ForegroundColor Cyan
Write-Host 'Restart the client instead of /reload if the branch added, removed' -ForegroundColor Cyan
Write-Host 'or renamed a file, or changed the .toc.' -ForegroundColor Cyan
