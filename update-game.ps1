# update-game.ps1 — Pizza Tycoon updater
# Usage: put this script AND pizza-tycoon.zip in your game root folder
# (the folder that contains src\, default.project.json), then run:
#   .\update-game.ps1
# It extracts the zip and overwrites the existing project files.
# Old files that no longer exist in the zip are NOT deleted.

param(
    # Path to the zip; defaults to pizza-tycoon.zip next to this script.
    [string]$ZipPath = "$PSScriptRoot\pizza-tycoon.zip",
    # Skip the timestamped backup of the current project.
    [switch]$NoBackup
)

$ErrorActionPreference = "Stop"

$root = $PSScriptRoot
$extractRoot = Join-Path $root "pizza-tycoon"

if (-not (Test-Path $ZipPath)) {
    Write-Host "ERROR: zip not found at '$ZipPath'" -ForegroundColor Red
    Write-Host "Put pizza-tycoon.zip in the same folder as this script (or pass -ZipPath)."
    exit 1
}

# 1) Backup current project (only if there is something to back up).
$srcDir = Join-Path $root "src"
$projFile = Join-Path $root "default.project.json"
if (-not $NoBackup -and (Test-Path $srcDir)) {
    $backup = Join-Path $root ("backup-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Path $backup | Out-Null
    Copy-Item -Path $srcDir -Destination $backup -Recurse
    if (Test-Path $projFile) {
        Copy-Item -Path $projFile -Destination $backup
    }
    Write-Host "Backup created: $backup" -ForegroundColor DarkGray
}

# 2) Extract the zip to a temp folder, then copy over the project.
$temp = Join-Path $env:TEMP ("pizza-tycoon-update-" + [guid]::NewGuid().ToString("N"))
Expand-Archive -Path $ZipPath -DestinationPath $temp -Force

$srcZip = Join-Path $temp "pizza-tycoon"
if (-not (Test-Path $srcZip)) {
    # Zip might not contain a top-level folder; handle that too.
    $srcZip = $temp
}

# 3) Mirror zip contents into the game root (overwrite on collision).
Copy-Item -Path (Join-Path $srcZip "*") -Destination $root -Recurse -Force

Remove-Item -Path $temp -Recurse -Force

# 4) Report.
$files = (Get-ChildItem -Path $srcDir -Recurse -File -Filter "*.luau").Count
Write-Host ""
Write-Host "Update complete. .luau files now in src\: $files" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  - If you use Rojo:  rojo serve default.project.json  (Studio syncs automatically)"
Write-Host "  - If you paste manually: copy the changed files into their matching scripts in Studio."
