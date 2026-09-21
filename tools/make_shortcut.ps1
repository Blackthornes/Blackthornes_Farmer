# Put "Import WoW Harvest" on the desktop. Run this once.
#
#     Right-click this file -> Run with PowerShell
#
# or, if Windows refuses to run scripts:
#
#     powershell -ExecutionPolicy Bypass -File tools\make_shortcut.ps1
#
# It points a desktop shortcut at "Import Harvest.bat" in this repository, so
# the shortcut keeps working after a git pull -- nothing is copied out, and the
# shortcut follows whatever the checkout does.
#
# -Remove deletes the shortcut again.

[CmdletBinding()]
param(
    [switch]$Remove,
    [string]$Name = "Import WoW Harvest"
)

$ErrorActionPreference = "Stop"

# tools\ -> the repository root.
$repo = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repo "Import Harvest.bat"
$icon = Join-Path $repo "tools\farmer.ico"

$desktop = [Environment]::GetFolderPath("Desktop")
$link = Join-Path $desktop "$Name.lnk"

if ($Remove) {
    if (Test-Path -LiteralPath $link) {
        Remove-Item -LiteralPath $link
        Write-Host "Removed $link"
    } else {
        Write-Host "Nothing to remove: no shortcut at $link"
    }
    return
}

# Fail loudly here rather than leaving a shortcut that opens nothing.
if (-not (Test-Path -LiteralPath $target)) {
    throw "Could not find $target. Run this from inside the repository."
}

if (-not (Test-Path -LiteralPath $desktop)) {
    throw "Could not find your Desktop folder at $desktop."
}

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($link)

$shortcut.TargetPath = $target
$shortcut.WorkingDirectory = $repo
$shortcut.Description = "Read what you harvested in WoW and write it into the addon's data"
$shortcut.WindowStyle = 1

if (Test-Path -LiteralPath $icon) {
    $shortcut.IconLocation = "$icon,0"
}

$shortcut.Save()

Write-Host ""
Write-Host "  Created: $link"
Write-Host "  Runs:    $target"
Write-Host ""
Write-Host "  Log out of WoW first, then double-click it." -ForegroundColor Green
Write-Host ""
