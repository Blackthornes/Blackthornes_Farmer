<#
.SYNOPSIS
    Bring every Blackthornes repo on this PC up to date with GitHub, safely.

.DESCRIPTION
    For each of the five addon repos, fetches its play branch and moves the
    checkout forward to it (Tradeskills plays from testing, the others from
    main). Then prints one line per repo and a summary saying whether /reload
    is enough or the game needs a full restart.

    It only ever fast-forwards. It never stashes, resets, merges, forces or
    switches branches. A repo with local changes, on another branch, or that
    has commits GitHub does not have is skipped and named, and left exactly
    as it was.

    A full restart is needed when the pulled range added, removed or renamed
    a file, or changed a .toc, Bindings.xml or a .tga: the client reads those
    only at startup.

    Exits 0 when every repo was handled, 1 when any was skipped.

.PARAMETER Root
    The folder that holds the repos. Defaults to D:\Blackthornes_Repo.

.EXAMPLE
    .\tools\sync_all.ps1
.EXAMPLE
    .\tools\sync_all.ps1 -Root E:\Addons
#>

[CmdletBinding()]
param(
    [string]$Root = 'D:\Blackthornes_Repo'
)

# Git writes progress and notes to stderr; Windows PowerShell 5.1 turns that
# into errors under 'Stop', so failures are judged by exit code instead.
$ErrorActionPreference = 'Continue'

# Never stop to ask for a password: a fetch that needs one fails and is named.
$env:GIT_TERMINAL_PROMPT = '0'

# Each repo and the branch the owner plays from.
$Repos = [ordered]@{
    'Blackthornes_Farmer'      = 'main'
    'Blackthornes_Tradeskills' = 'testing'
    'Blackthornes_Equipment'   = 'main'
    'Blackthornes_Pets'        = 'main'
    'Blackthornes_Butler'      = 'main'
}

# Runs git in a repo. Returns its exit code and stdout lines; stderr is
# dropped so nothing it says (a remote address, a credential prompt's text)
# is printed.
function Invoke-Git {
    param([string]$Path, [string[]]$GitArgs)
    $output = & git -C $Path @GitArgs 2>$null
    return @{ Code = $LASTEXITCODE; Out = @($output) }
}

# True when the pulled range needs a full restart rather than /reload.
# Lines are `git diff --name-status` output: a status letter, a tab, paths.
function Test-NeedsRestart {
    param([string[]]$NameStatus)
    foreach ($line in $NameStatus) {
        if (-not $line) { continue }
        $parts = $line -split "`t"
        if ($parts[0] -match '^[ADRC]') { return $true }
        if ($parts.Count -lt 2) { continue }
        foreach ($p in $parts[1..($parts.Count - 1)]) {
            if ($p -match '\.(toc|tga)$' -or $p -match '(^|/)Bindings\.xml$') { return $true }
        }
    }
    return $false
}

function Get-Short { param([string]$Sha) return $Sha.Substring(0, 7) }

$updated = 0
$current = 0
$skipped = @()
$restartFor = @()

foreach ($name in $Repos.Keys) {
    $branch = $Repos[$name]
    $path = Join-Path $Root $name
    $label = "$name ($branch)"

    if (-not (Test-Path (Join-Path $path '.git'))) {
        Write-Output "$label`: skipped, no git repo at $path."
        $skipped += $name
        continue
    }

    $head = Invoke-Git $path @('rev-parse', '--abbrev-ref', 'HEAD')
    $onBranch = ($head.Out | Select-Object -First 1)
    if ($head.Code -ne 0 -or $onBranch -ne $branch) {
        if (-not $onBranch) { $onBranch = 'unknown' }
        Write-Output "$label`: skipped, it is on $onBranch, not $branch. Nothing was changed."
        $skipped += $name
        continue
    }

    $dirty = Invoke-Git $path @('status', '--porcelain', '--untracked-files=no')
    if ($dirty.Code -ne 0) {
        Write-Output "$label`: skipped, git could not read its status."
        $skipped += $name
        continue
    }
    $changed = @($dirty.Out | Where-Object { $_ })
    if ($changed.Count -gt 0) {
        Write-Output "$label`: skipped, $($changed.Count) file(s) changed on this PC. Nothing was changed."
        $skipped += $name
        continue
    }

    $fetch = Invoke-Git $path @('fetch', '--quiet', 'origin', $branch)
    if ($fetch.Code -ne 0) {
        Write-Output "$label`: skipped, could not fetch from GitHub (offline, or no access)."
        $skipped += $name
        continue
    }

    $old = (Invoke-Git $path @('rev-parse', 'HEAD')).Out | Select-Object -First 1
    $new = (Invoke-Git $path @('rev-parse', "origin/$branch")).Out | Select-Object -First 1
    if (-not $old -or -not $new) {
        Write-Output "$label`: skipped, git could not read the commits."
        $skipped += $name
        continue
    }

    if ($old -eq $new) {
        Write-Output "$label`: already up to date at $(Get-Short $old)."
        $current++
        continue
    }

    $behind = Invoke-Git $path @('merge-base', '--is-ancestor', 'HEAD', "origin/$branch")
    if ($behind.Code -ne 0) {
        $ahead = Invoke-Git $path @('merge-base', '--is-ancestor', "origin/$branch", 'HEAD')
        if ($ahead.Code -eq 0) {
            Write-Output "$label`: skipped, it has commits GitHub does not have. Nothing was changed."
        } else {
            Write-Output "$label`: skipped, it has split from GitHub and cannot fast-forward. Nothing was changed."
        }
        $skipped += $name
        continue
    }

    $diff = Invoke-Git $path @('diff', '--name-status', '-M', $old, $new)
    $merge = Invoke-Git $path @('merge', '--ff-only', '--quiet', "origin/$branch")
    if ($merge.Code -ne 0) {
        Write-Output "$label`: skipped, the fast-forward was refused (a file here may be in the way). Nothing was changed."
        $skipped += $name
        continue
    }

    $files = @($diff.Out | Where-Object { $_ }).Count
    $needsRestart = Test-NeedsRestart $diff.Out
    if ($needsRestart) {
        $restartFor += $name
        $after = 'needs a full restart.'
    } else {
        $after = '/reload is enough.'
    }
    Write-Output "$label`: updated $(Get-Short $old) -> $(Get-Short $new), $files file(s), $after"
    $updated++
}

$summary = "Done: $updated updated, $current already up to date, $($skipped.Count) skipped."
if ($restartFor.Count -gt 0) {
    $summary += " Restart the game fully (for $($restartFor -join ', '))."
} elseif ($updated -gt 0) {
    $summary += ' /reload in game is enough.'
} else {
    $summary += ' Nothing new to load.'
}
if ($skipped.Count -gt 0) {
    $summary += " Skipped: $($skipped -join ', ')."
}
Write-Output $summary

if ($skipped.Count -gt 0) { exit 1 }
exit 0
