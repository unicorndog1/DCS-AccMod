param(
    [string]$RepoRoot = "C:\HELL\CODE\DCS-AccMod",
    [switch]$IncludeSavedGamesMods = $true,
    [string]$SavedGamesRoot,
    [string]$SavedGamesProfile = "DCS",
    [int]$MaxSavedGamesFiles = 8000,
    [int]$MaxLuaFileSizeKB = 512
)

$ErrorActionPreference = 'Stop'

$builderScript = Join-Path $RepoRoot 'Scripts\build_unit_placer_catalog.ps1'
if (-not (Test-Path $builderScript)) {
    throw "Builder script not found: $builderScript"
}

$builderParams = @{
    RepoRoot = $RepoRoot
    IncludeSavedGamesMods = $IncludeSavedGamesMods
    SavedGamesProfile = $SavedGamesProfile
    MaxSavedGamesFiles = $MaxSavedGamesFiles
    MaxLuaFileSizeKB = $MaxLuaFileSizeKB
}

if (-not [string]::IsNullOrWhiteSpace($SavedGamesRoot)) {
    $builderParams.SavedGamesRoot = $SavedGamesRoot
}

& $builderScript @builderParams

if ([string]::IsNullOrWhiteSpace($SavedGamesRoot)) {
    $SavedGamesRoot = Join-Path $env:USERPROFILE (Join-Path 'Saved Games' $SavedGamesProfile)
}

$repoScript = Join-Path $RepoRoot 'Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua'
$repoDb = Join-Path $RepoRoot 'Mods\Services\DCS-AccWidg\Scripts\UnitPlacerCatalogDB.lua'
$liveScriptsDir = Join-Path $SavedGamesRoot 'Mods\Services\DCS-AccWidg\Scripts'
$liveScript = Join-Path $liveScriptsDir 'DCS-SRS-AccMod.lua'
$liveDb = Join-Path $liveScriptsDir 'UnitPlacerCatalogDB.lua'

if (-not (Test-Path $liveScriptsDir)) {
    New-Item -Path $liveScriptsDir -ItemType Directory -Force | Out-Null
}

Copy-Item -Path $repoScript -Destination $liveScript -Force
Copy-Item -Path $repoDb -Destination $liveDb -Force

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$text = [System.IO.File]::ReadAllText($liveDb)
[System.IO.File]::WriteAllText($liveDb, $text, $utf8NoBom)

Write-Output ('DEPLOYED_TO=' + $liveScriptsDir)
