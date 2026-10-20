# Builds the evaluator packages from the current checkout (Windows PowerShell 5.1+).
#   build\web\                                 web export (index.html at the root)
#   build\windows\DroneAcharya-<ver>-win64\    Windows export + README + licence
#   build\release\DroneAcharya-<ver>-web.zip   upload to itch.io as an HTML game
#   build\release\DroneAcharya-<ver>-win64.zip attach to a GitHub Release
# Needs Godot 4.7.2 in the repo root (see README) and its official export templates
# installed in %APPDATA%\Godot\export_templates\4.7.2.stable\. Uploads nothing.
#
# Usage, from the repo root:  .\deploy\build-release.ps1 [-Version 2026.10.20] [-Target Windows|Web|All]

param(
    [string]$Version = (Get-Date -Format "yyyy.MM.dd"),
    [string]$Godot = ".\Godot_v4.7.2-stable_win64_console.exe",
    [ValidateSet("All", "Windows", "Web")]
    [string]$Target = "All"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
if (-not (Test-Path $Godot)) { throw "Godot not found at $Godot (see README, Requirements)." }
$commit = (git rev-parse --short HEAD).Trim()
$dirty = git status --porcelain --untracked-files=no
if ($dirty) { Write-Warning "Uncommitted changes are included in this build; the commit id alone does not describe it." }

function Export-Preset([string]$preset, [string]$target) {
    & $Godot --headless --path simulator --export-release $preset $target | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Godot export '$preset' failed (exit $LASTEXITCODE)." }
}

function New-Zip([string]$zip, [string]$fromDir, [string[]]$items) {
    if (Test-Path $zip) { Remove-Item $zip }
    & tar.exe -a -c -f $zip -C $fromDir @items
    if ($LASTEXITCODE -ne 0) { throw "Could not create $zip." }
}

New-Item -ItemType Directory -Force build\release | Out-Null
$zips = @()

if ($Target -ne "Windows") {
    # Web: the folder is emptied first so no stale files end up in the ZIP.
    $web = "build\web"
    New-Item -ItemType Directory -Force $web | Out-Null
    Get-ChildItem $web | Remove-Item -Recurse -Force
    Export-Preset "Web" "../build/web/index.html"
    Copy-Item deploy\licenses\GODOT_LICENSE.txt, deploy\licenses\DEJAVU_FONT_LICENSE.txt $web
    $webZip = "build\release\DroneAcharya-$Version-web.zip"
    New-Zip $webZip $web @((Get-ChildItem $web).Name)
    $zips += $webZip
}

if ($Target -ne "Web") {
    # Windows: one folder with the executable (data embedded), README and licence.
    $name = "DroneAcharya-$Version-win64"
    $win = "build\windows\$name"
    if (Test-Path $win) { Remove-Item $win -Recurse -Force }
    New-Item -ItemType Directory -Force $win | Out-Null
    Export-Preset "Windows Desktop" "../$win/DroneAcharya.exe"
    (Get-Content deploy\windows\README.txt -Raw -Encoding UTF8).Replace("{VERSION}", $Version).Replace("{COMMIT}", $commit) |
        Set-Content -Encoding utf8 "$win\README.txt"
    Copy-Item deploy\licenses\GODOT_LICENSE.txt $win
    $winZip = "build\release\$name.zip"
    New-Zip $winZip "build\windows" @($name)
    $zips += $winZip
}

foreach ($zip in $zips) {
    $item = Get-Item $zip
    $hash = (Get-FileHash $zip -Algorithm SHA256).Hash
    "{0}  {1:N1} MB  SHA256 {2}" -f $item.FullName, ($item.Length / 1MB), $hash
}
