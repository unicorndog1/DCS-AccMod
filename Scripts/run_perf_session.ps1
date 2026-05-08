#requires -Version 5.1
<#
.SYNOPSIS
    Wrapper for an asynchronous DCS-AccMod VR overlay perf session.

.DESCRIPTION
    Captures build/code identity into runs/<RUN_ID>/manifest.json, sets env
    vars consumed by both the OpenXR layer DLL and the Lua mod, truncates
    the four perf-relevant log files, then waits for the user to start and
    finish DCS. On completion, copies all logs into runs/<RUN_ID>/.

.PARAMETER Scenario
    Logical scenario tag (idle | static_50 | jitter_100 | live_caucasus | <freeform>).

.PARAMETER Phase
    Implementation phase tag (e.g. phase0_baseline, phase1_dirty_flag, phase3_gpu).

.PARAMETER NoLaunchDcs
    If set, the wrapper only prepares the run and prints "Start DCS now"; it
    does not attempt to launch DCS.exe automatically.

.EXAMPLE
    .\Scripts\run_perf_session.ps1 -Scenario static_50 -Phase phase0_baseline

    Creates runs/<RUN_ID>/, sets env vars, truncates logs, waits for keypress,
    then collects logs.
#>

[CmdletBinding()]
param(
    [string]$Scenario = "idle",
    [string]$Phase    = "phase0_baseline",
    [switch]$NoLaunchDcs
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $PSScriptRoot
$runsRoot   = Join-Path $repoRoot 'runs'
$savedGames = Join-Path $env:USERPROFILE 'Saved Games\DCS'
$dcsLog     = Join-Path $savedGames 'Logs\dcs.log'
$luaCsv     = Join-Path $savedGames 'Logs\AccMod_perf.csv'
$xrLog      = Join-Path $env:TEMP 'DCS_AccMod_OpenXR.log'
$xrCsv      = Join-Path $env:TEMP 'DCS_AccMod_OpenXR_perf.csv'

$dllRepo  = Join-Path $repoRoot 'OpenXR-Layer\DCS_AccMod_OpenXR_Layer.dll'
$luaRepo  = Join-Path $repoRoot 'Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua'
$luaSaved = Join-Path $savedGames 'Mods\Services\DCS-AccWidg\Scripts\DCS-SRS-AccMod.lua'

function Get-GitInfo {
    $info = [ordered]@{
        sha    = 'nogit'
        short  = 'nogit'
        dirty  = $false
        dirtyFiles = @()
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $info }
    Push-Location $repoRoot
    try {
        $sha = git rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0 -and $sha) {
            $info.sha = $sha.Trim()
            $info.short = $info.sha.Substring(0, [Math]::Min(10, $info.sha.Length))
        }
        $status = git status --porcelain 2>$null
        if ($LASTEXITCODE -eq 0 -and $status) {
            $info.dirty = $true
            $info.dirtyFiles = ($status -split "`n" | Where-Object { $_ }) | ForEach-Object { $_.Trim() }
        }
    } finally { Pop-Location }
    return $info
}

function Get-FileFingerprint($path) {
    if (-not (Test-Path $path)) {
        return [ordered]@{ path = $path; exists = $false }
    }
    $h = Get-FileHash -Algorithm SHA256 -Path $path
    $i = Get-Item $path
    return [ordered]@{
        path   = $path
        exists = $true
        sha256 = $h.Hash.ToLower()
        size   = $i.Length
        mtime  = $i.LastWriteTimeUtc.ToString('o')
    }
}

function Truncate-File($path) {
    if (Test-Path $path) {
        try { Set-Content -Path $path -Value '' -Encoding ASCII -Force } catch {
            Write-Warning ("Could not truncate {0}: {1}" -f $path, $_.Exception.Message)
        }
    }
}

# --- Build run identity ----------------------------------------------------
$git    = Get-GitInfo
$ts     = Get-Date -Format 'yyyyMMdd-HHmmss'
$dirtyTag = if ($git.dirty) { 'dirty' } else { 'clean' }
$runId  = "$ts-$($git.short)-$dirtyTag"
$runDir = Join-Path $runsRoot $runId
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$manifest = [ordered]@{
    run_id     = $runId
    started_utc= (Get-Date).ToUniversalTime().ToString('o')
    scenario   = $Scenario
    phase      = $Phase
    git        = $git
    dll_repo   = Get-FileFingerprint $dllRepo
    lua_repo   = Get-FileFingerprint $luaRepo
    lua_saved  = Get-FileFingerprint $luaSaved
    host       = [ordered]@{
        os       = [Environment]::OSVersion.VersionString
        machine  = $env:COMPUTERNAME
        user     = $env:USERNAME
        cpu      = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
    }
    artifacts  = [ordered]@{
        dcs_log  = $dcsLog
        lua_csv  = $luaCsv
        xr_log   = $xrLog
        xr_csv   = $xrCsv
    }
}

$manifestPath = Join-Path $runDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8

# --- Set env vars (this process and child DCS, if launched here) ----------
$env:ACCMOD_RUN_ID    = $runId
$env:ACCMOD_PHASE     = $Phase
$env:ACCMOD_SCENARIO  = $Scenario
$env:ACCMOD_GIT_SHA   = $git.sha
$env:ACCMOD_GIT_DIRTY = if ($git.dirty) { '1' } else { '0' }

Write-Host "==== ACCMOD perf run prepared ====" -ForegroundColor Cyan
Write-Host "  RUN_ID   : $runId"
Write-Host "  Scenario : $Scenario"
Write-Host "  Phase    : $Phase"
Write-Host "  Manifest : $manifestPath"
Write-Host "  DLL sha  : $($manifest.dll_repo.sha256)"
Write-Host "  Lua repo : $($manifest.lua_repo.sha256)"
Write-Host "  Lua saved: $($manifest.lua_saved.sha256)"
if ($git.dirty) {
    Write-Host "  Git      : DIRTY ($($git.dirtyFiles.Count) file(s))" -ForegroundColor Yellow
} else {
    Write-Host "  Git      : clean ($($git.short))"
}
Write-Host ""

if ($manifest.lua_repo.exists -and $manifest.lua_saved.exists -and
    $manifest.lua_repo.sha256 -ne $manifest.lua_saved.sha256) {
    Write-Warning "Lua repo and Saved Games copies differ. Run deploy.bat before starting DCS to ensure the build under test matches the manifest."
}

# --- Truncate logs --------------------------------------------------------
Write-Host "Truncating logs..." -ForegroundColor Cyan
foreach ($p in @($dcsLog, $luaCsv, $xrLog, $xrCsv)) {
    Truncate-File $p
}

# --- Hand off to user (or launch DCS) -------------------------------------
if ($NoLaunchDcs) {
    Write-Host ""
    Write-Host "Start DCS NOW (env vars are set in this PowerShell session)." -ForegroundColor Green
    Write-Host "When DCS is closed, press ENTER here to collect artifacts."
    [void](Read-Host)
} else {
    $dcsExe = $null
    foreach ($cand in @(
        'C:\Program Files\Eagle Dynamics\DCS World OpenBeta\bin\DCS.exe',
        'C:\Program Files\Eagle Dynamics\DCS World\bin\DCS.exe'
    )) {
        if (Test-Path $cand) { $dcsExe = $cand; break }
    }

    if ($dcsExe) {
        Write-Host "Launching: $dcsExe" -ForegroundColor Green
        Start-Process -FilePath $dcsExe -PassThru | Out-Null
        Write-Host "Press ENTER here when the DCS run is finished to collect artifacts." -ForegroundColor Yellow
        [void](Read-Host)
    } else {
        Write-Host "DCS.exe not auto-detected. Start DCS manually now." -ForegroundColor Yellow
        Write-Host "Press ENTER when finished."
        [void](Read-Host)
    }
}

# --- Collect artifacts ----------------------------------------------------
Write-Host "Collecting artifacts into $runDir ..." -ForegroundColor Cyan
foreach ($p in @($dcsLog, $luaCsv, $xrLog, $xrCsv)) {
    if (Test-Path $p) {
        Copy-Item -Path $p -Destination $runDir -Force
        Write-Host "  copied: $p"
    } else {
        Write-Warning "missing: $p"
    }
}

# Re-fingerprint after the run so we capture the *actual* code that ran (the
# Saved Games copy might differ from the repo if user ran deploy.bat).
$manifest.lua_saved_after = Get-FileFingerprint $luaSaved
$manifest.dll_repo_after  = Get-FileFingerprint $dllRepo
$manifest.finished_utc    = (Get-Date).ToUniversalTime().ToString('o')
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8

Write-Host ""
Write-Host "Run complete: $runDir" -ForegroundColor Green
Write-Host "Ingestion: tell the agent 'ingest run $runId'."
