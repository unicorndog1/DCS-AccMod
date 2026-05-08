param(
    [Parameter(Mandatory = $true)]
    [string]$SourceMiz,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputMiz,

    [switch]$DryRun,
    [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Write-Info([string]$msg) {
    Write-Host "[AccMod-Reintegrate] $msg"
}

function Replace-Range {
    param(
        [string]$Text,
        [int]$Start,
        [int]$End,
        [string]$Replacement
    )

    if ($Start -lt 0 -or $End -lt $Start -or $End -ge $Text.Length) {
        throw "Invalid replace range [$Start,$End] on text length $($Text.Length)"
    }

    return $Text.Substring(0, $Start) + $Replacement + $Text.Substring($End + 1)
}

function Get-MatchingBraceIndex {
    param(
        [string]$Text,
        [int]$OpenBraceIndex
    )

    if ($OpenBraceIndex -lt 0 -or $OpenBraceIndex -ge $Text.Length -or $Text[$OpenBraceIndex] -ne '{') {
        throw "Get-MatchingBraceIndex expected '{' at index $OpenBraceIndex"
    }

    $depth = 0
    $inSingle = $false
    $inDouble = $false
    $escaped = $false

    for ($i = $OpenBraceIndex; $i -lt $Text.Length; $i++) {
        $ch = $Text[$i]

        if ($escaped) {
            $escaped = $false
            continue
        }

        if ($inSingle) {
            if ($ch -eq '\\') {
                $escaped = $true
            }
            elseif ($ch -eq "'") {
                $inSingle = $false
            }
            continue
        }

        if ($inDouble) {
            if ($ch -eq '\\') {
                $escaped = $true
            }
            elseif ($ch -eq '"') {
                $inDouble = $false
            }
            continue
        }

        if ($ch -eq "'") {
            $inSingle = $true
            continue
        }

        if ($ch -eq '"') {
            $inDouble = $true
            continue
        }

        if ($ch -eq '{') {
            $depth++
            continue
        }

        if ($ch -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $i
            }
        }
    }

    throw "No matching closing brace found for index $OpenBraceIndex"
}

function Find-KeyTableRange {
    param(
        [string]$Text,
        [string]$Key,
        [int]$SearchStart,
        [int]$SearchEnd
    )

    if ($SearchEnd -lt $SearchStart) {
        return $null
    }

    $segment = $Text.Substring($SearchStart, $SearchEnd - $SearchStart + 1)
    $escapedKey = [Regex]::Escape($Key)
    $pattern = '(?s)(\[\s*["'']{0}["'']\s*\]|\b{0}\b)\s*=\s*\{' -f $escapedKey
    $match = [Regex]::Match($segment, $pattern)
    if (-not $match.Success) {
        return $null
    }

    $abs = $SearchStart + $match.Index
    $eqIndex = $Text.IndexOf('=', $abs)
    if ($eqIndex -lt 0 -or $eqIndex -gt $SearchEnd) {
        return $null
    }

    $braceIndex = $Text.IndexOf('{', $eqIndex)
    if ($braceIndex -lt 0 -or $braceIndex -gt $SearchEnd) {
        return $null
    }

    $close = Get-MatchingBraceIndex -Text $Text -OpenBraceIndex $braceIndex
    if ($close -gt $SearchEnd) {
        return $null
    }

    return [pscustomobject]@{
        Start = $braceIndex
        End = $close
        AssignStart = $abs
    }
}

function Get-TopLevelArrayEntries {
    param(
        [string]$Text,
        [int]$TableStart,
        [int]$TableEnd
    )

    $entries = New-Object System.Collections.ArrayList
    $i = $TableStart + 1

    while ($i -lt $TableEnd) {
        $ch = $Text[$i]

        if ($ch -eq '[') {
            $remaining = $Text.Substring($i, $TableEnd - $i + 1)
            $m = [Regex]::Match($remaining, '^\[(\d+)\]\s*=\s*\{')
            if ($m.Success) {
                $idx = [int]$m.Groups[1].Value
                $braceOffset = $m.Value.LastIndexOf('{')
                $entryStart = $i + $braceOffset
                $entryEnd = Get-MatchingBraceIndex -Text $Text -OpenBraceIndex $entryStart

                [void]$entries.Add([pscustomobject]@{
                    Index = $idx
                    Start = $entryStart
                    End = $entryEnd
                    Text = $Text.Substring($entryStart, $entryEnd - $entryStart + 1)
                })

                $i = $entryEnd + 1
                continue
            }
        }

        $i++
    }

    return $entries
}

function Get-NextArrayIndex {
    param(
        [System.Collections.ArrayList]$Entries
    )

    $max = 0
    foreach ($e in $Entries) {
        if ($e.Index -gt $max) {
            $max = $e.Index
        }
    }
    return ($max + 1)
}

function Get-MaxNumericByPattern {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $max = 0
    foreach ($m in [Regex]::Matches($Text, $Pattern)) {
        $value = 0
        if ([int]::TryParse($m.Groups[1].Value, [ref]$value)) {
            if ($value -gt $max) {
                $max = $value
            }
        }
    }
    return $max
}

function Escape-LuaString([string]$Value) {
    if ($null -eq $Value) {
        return ""
    }

    return $Value.Replace('\\', '\\\\').Replace('"', '\\"')
}

function Parse-LuaRecordFields {
    param(
        [string]$RecordText
    )

    $obj = @{}

    foreach ($m in [Regex]::Matches($RecordText, '(?m)\b([A-Za-z0-9_]+)\s*=\s*"((?:\\.|[^"\\])*)"')) {
        $k = $m.Groups[1].Value
        $v = $m.Groups[2].Value -replace '\\"', '"' -replace '\\\\', '\\'
        $obj[$k] = $v
    }

    foreach ($m in [Regex]::Matches($RecordText, "(?m)\b([A-Za-z0-9_]+)\s*=\s*'((?:\\.|[^'\\])*)'")) {
        $k = $m.Groups[1].Value
        if (-not $obj.ContainsKey($k)) {
            $v = $m.Groups[2].Value -replace "\\'", "'" -replace '\\\\', '\\'
            $obj[$k] = $v
        }
    }

    foreach ($m in [Regex]::Matches($RecordText, '(?m)\b([A-Za-z0-9_]+)\s*=\s*(-?\d+(?:\.\d+)?)')) {
        $k = $m.Groups[1].Value
        if (-not $obj.ContainsKey($k)) {
            $num = [double]::Parse($m.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture)
            $obj[$k] = $num
        }
    }

    foreach ($m in [Regex]::Matches($RecordText, '(?m)\b([A-Za-z0-9_]+)\s*=\s*(true|false)')) {
        $k = $m.Groups[1].Value
        if (-not $obj.ContainsKey($k)) {
            $obj[$k] = ($m.Groups[2].Value -eq 'true')
        }
    }

    return $obj
}

function Parse-ManifestLua {
    param(
        [string]$ManifestText
    )

    $recordsRange = Find-KeyTableRange -Text $ManifestText -Key "records" -SearchStart 0 -SearchEnd ($ManifestText.Length - 1)
    if (-not $recordsRange) {
        throw "Manifest does not contain records table"
    }

    $entries = Get-TopLevelArrayEntries -Text $ManifestText -TableStart $recordsRange.Start -TableEnd $recordsRange.End
    $records = New-Object System.Collections.ArrayList

    foreach ($entry in $entries) {
        $fields = Parse-LuaRecordFields -RecordText $entry.Text
        [void]$records.Add($fields)
    }

    return $records
}

function Resolve-SideName {
    param([hashtable]$Record)

    if ($Record.ContainsKey("coalition")) {
        $coalition = [int]$Record["coalition"]
        if ($coalition -eq 1) { return "red" }
        if ($coalition -eq 2) { return "blue" }
        if ($coalition -eq 0) { return "neutrals" }
    }

    return "blue"
}

function Build-GroupEntryLua {
    param(
        [hashtable]$Record,
        [int]$EntryIndex,
        [int]$GroupId,
        [int]$UnitId
    )

    $groupName = Escape-LuaString ([string]$Record["groupName"])
    $unitName = Escape-LuaString ([string]$Record["unitName"])
    $typeName = Escape-LuaString ([string]$Record["typeName"])

    $x = [double]$Record["x"]
    $z = [double]$Record["z"]
    $heading = 0.0
    if ($Record.ContainsKey("heading")) {
        $heading = [double]$Record["heading"]
    }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    $xStr = $x.ToString("0.###", $inv)
    $zStr = $z.ToString("0.###", $inv)
    $hStr = $heading.ToString("0.######", $inv)

    return @"
        [$EntryIndex] =
        {
            ["visible"] = true,
            ["taskSelected"] = true,
            ["route"] =
            {
                ["points"] =
                {
                },
            },
            ["groupId"] = $GroupId,
            ["tasks"] =
            {
            },
            ["hidden"] = false,
            ["units"] =
            {
                [1] =
                {
                    ["type"] = "$typeName",
                    ["unitId"] = $UnitId,
                    ["skill"] = "Average",
                    ["y"] = $zStr,
                    ["x"] = $xStr,
                    ["name"] = "$unitName",
                    ["heading"] = $hStr,
                },
            },
            ["y"] = $zStr,
            ["x"] = $xStr,
            ["name"] = "$groupName",
            ["start_time"] = 0,
        },
"@
}

function Ensure-KeyTable {
    param(
        [string]$Text,
        [int]$ParentStart,
        [int]$ParentEnd,
        [string]$Key,
        [string]$TableInitializer
    )

    $found = Find-KeyTableRange -Text $Text -Key $Key -SearchStart $ParentStart -SearchEnd $ParentEnd
    if ($found) {
        return [pscustomobject]@{
            Text = $Text
            Range = $found
        }
    }

    $insertAt = $ParentEnd
    $insertion = "`n$TableInitializer`n"
    $newText = $Text.Substring(0, $insertAt) + $insertion + $Text.Substring($insertAt)

    # Recompute parent end and find inserted table.
    $newParentEnd = $ParentEnd + $insertion.Length
    $newRange = Find-KeyTableRange -Text $newText -Key $Key -SearchStart $ParentStart -SearchEnd $newParentEnd
    if (-not $newRange) {
        throw "Failed to create missing table key '$Key'"
    }

    return [pscustomobject]@{
        Text = $newText
        Range = $newRange
    }
}

function Insert-RecordIntoMission {
    param(
        [string]$MissionText,
        [hashtable]$Record,
        [int]$GroupId,
        [int]$UnitId
    )

    $countryName = [string]$Record["countryName"]
    if ([string]::IsNullOrWhiteSpace($countryName)) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Missing countryName" }
    }

    $sideName = Resolve-SideName -Record $Record

    $coalitionRange = Find-KeyTableRange -Text $MissionText -Key "coalition" -SearchStart 0 -SearchEnd ($MissionText.Length - 1)
    if (-not $coalitionRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Mission missing coalition table" }
    }

    $sideRange = Find-KeyTableRange -Text $MissionText -Key $sideName -SearchStart $coalitionRange.Start -SearchEnd $coalitionRange.End
    if (-not $sideRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Mission missing side '$sideName'" }
    }

    $countryRange = Find-KeyTableRange -Text $MissionText -Key "country" -SearchStart $sideRange.Start -SearchEnd $sideRange.End
    if (-not $countryRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Mission missing country table for side '$sideName'" }
    }

    $countryEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $countryRange.Start -TableEnd $countryRange.End
    $targetCountry = $null

    $countryPattern = '(?m)\bname\s*=\s*["'']{0}["'']' -f ([Regex]::Escape($countryName))

    foreach ($entry in $countryEntries) {
        if ($entry.Text -match $countryPattern) {
            $targetCountry = $entry
            break
        }
    }

    if (-not $targetCountry) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Country '$countryName' not found under side '$sideName'" }
    }

    $vehicleResult = Ensure-KeyTable -Text $MissionText -ParentStart $targetCountry.Start -ParentEnd $targetCountry.End -Key "vehicle" -TableInitializer "[\"vehicle\"] = { [\"group\"] = {} },"
    $MissionText = $vehicleResult.Text

    # Country range may have shifted, refetch target country.
    $coalitionRange = Find-KeyTableRange -Text $MissionText -Key "coalition" -SearchStart 0 -SearchEnd ($MissionText.Length - 1)
    $sideRange = Find-KeyTableRange -Text $MissionText -Key $sideName -SearchStart $coalitionRange.Start -SearchEnd $coalitionRange.End
    $countryRange = Find-KeyTableRange -Text $MissionText -Key "country" -SearchStart $sideRange.Start -SearchEnd $sideRange.End
    $countryEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $countryRange.Start -TableEnd $countryRange.End
    $targetCountry = $null
    foreach ($entry in $countryEntries) {
        if ($entry.Text -match $countryPattern) {
            $targetCountry = $entry
            break
        }
    }

    if (-not $targetCountry) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Country '$countryName' lookup failed after vehicle ensure" }
    }

    $vehicleRange = Find-KeyTableRange -Text $MissionText -Key "vehicle" -SearchStart $targetCountry.Start -SearchEnd $targetCountry.End
    if (-not $vehicleRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Vehicle table lookup failed for '$countryName'" }
    }

    $groupResult = Ensure-KeyTable -Text $MissionText -ParentStart $vehicleRange.Start -ParentEnd $vehicleRange.End -Key "group" -TableInitializer "[\"group\"] = {}"
    $MissionText = $groupResult.Text

    # Refresh all relevant ranges after mutation.
    $coalitionRange = Find-KeyTableRange -Text $MissionText -Key "coalition" -SearchStart 0 -SearchEnd ($MissionText.Length - 1)
    $sideRange = Find-KeyTableRange -Text $MissionText -Key $sideName -SearchStart $coalitionRange.Start -SearchEnd $coalitionRange.End
    $countryRange = Find-KeyTableRange -Text $MissionText -Key "country" -SearchStart $sideRange.Start -SearchEnd $sideRange.End
    $countryEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $countryRange.Start -TableEnd $countryRange.End
    $targetCountry = $null
    foreach ($entry in $countryEntries) {
        if ($entry.Text -match $countryPattern) {
            $targetCountry = $entry
            break
        }
    }

    $vehicleRange = Find-KeyTableRange -Text $MissionText -Key "vehicle" -SearchStart $targetCountry.Start -SearchEnd $targetCountry.End
    $groupRange = Find-KeyTableRange -Text $MissionText -Key "group" -SearchStart $vehicleRange.Start -SearchEnd $vehicleRange.End

    $groupEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $groupRange.Start -TableEnd $groupRange.End
    $nextIndex = Get-NextArrayIndex -Entries $groupEntries

    $entryLua = Build-GroupEntryLua -Record $Record -EntryIndex $nextIndex -GroupId $GroupId -UnitId $UnitId
    $insertAt = $groupRange.End
    $MissionText = $MissionText.Substring(0, $insertAt) + "`n$entryLua" + $MissionText.Substring($insertAt)

    return [pscustomobject]@{
        Success = $true
        Text = $MissionText
        Message = "Inserted $($Record.groupName)/$($Record.unitName) into $sideName/$countryName"
    }
}

# ----------------- Main -----------------

$sourceFull = (Resolve-Path $SourceMiz).Path
$manifestFull = (Resolve-Path $ManifestPath).Path
$outputFull = [System.IO.Path]::GetFullPath($OutputMiz)

if (-not (Test-Path $sourceFull)) {
    throw "Source .miz not found: $sourceFull"
}
if (-not (Test-Path $manifestFull)) {
    throw "Manifest not found: $manifestFull"
}
if ([string]::Equals($sourceFull, $outputFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Output must differ from source .miz"
}

$manifestText = [System.IO.File]::ReadAllText($manifestFull)
$records = Parse-ManifestLua -ManifestText $manifestText


# Separate group and static records
$groupRecords = @()
$staticRecords = @()
foreach ($r in $records) {
    if (-not $r.ContainsKey("typeName") -or -not $r.ContainsKey("x") -or -not $r.ContainsKey("z") -or -not $r.ContainsKey("countryName")) {
        continue
    }
    if ($r.ContainsKey("kind") -and [string]$r["kind"] -eq "static") {
        $staticRecords += ,$r
    } elseif (($r.ContainsKey("kind") -and [string]$r["kind"] -eq "group") -or (-not $r.ContainsKey("kind"))) {
        # Default to group if kind missing
        if ($r.ContainsKey("groupName") -and $r.ContainsKey("unitName")) {
            $groupRecords += ,$r
        }
    }
}

Write-Info "Loaded manifest records: $($records.Count)"
Write-Info "Eligible group records: $($groupRecords.Count)"
Write-Info "Eligible static records: $($staticRecords.Count)"

if (($groupRecords.Count + $staticRecords.Count) -eq 0) {
    throw "No eligible group or static records in manifest"
}


if ($DryRun) {
    Write-Info "DryRun enabled. No mission files will be modified."
    foreach ($r in $groupRecords) {
        $side = Resolve-SideName -Record $r
        Write-Info ("Would insert {0}/{1} type={2} into {3}/{4} at x={5} z={6}" -f $r.groupName, $r.unitName, $r.typeName, $side, $r.countryName, $r.x, $r.z)
    }
    foreach ($r in $staticRecords) {
        $side = Resolve-SideName -Record $r
        Write-Info ("Would insert static {0} type={1} into {2}/{3} at x={4} z={5}" -f $r.unitName, $r.typeName, $side, $r.countryName, $r.x, $r.z)
    }
    exit 0
}

# Start from a copied mission as requested.
Copy-Item -LiteralPath $sourceFull -Destination $outputFull -Force

$tempRoot = Join-Path $env:TEMP ("AccModMizPatch_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

try {
    [System.IO.Compression.ZipFile]::ExtractToDirectory($outputFull, $tempRoot)

    $missionPath = Join-Path $tempRoot "mission"
    if (-not (Test-Path $missionPath)) {
        throw "Extracted mission archive missing 'mission' file"
    }

    $missionText = [System.IO.File]::ReadAllText($missionPath)

    $maxGroupId = Get-MaxNumericByPattern -Text $missionText -Pattern '(?m)\["groupId"\]\s*=\s*(\d+)'
    $maxUnitId = Get-MaxNumericByPattern -Text $missionText -Pattern '(?m)\["unitId"\]\s*=\s*(\d+)'

    $groupId = $maxGroupId + 1
    $unitId = $maxUnitId + 1


    $inserted = 0
    $skipped = New-Object System.Collections.ArrayList

    foreach ($r in $groupRecords) {
        $res = Insert-RecordIntoMission -MissionText $missionText -Record $r -GroupId $groupId -UnitId $unitId
        if ($res.Success) {
            $missionText = $res.Text
            $inserted++
            Write-Info $res.Message
            $groupId++
            $unitId++
        }
        else {
            [void]$skipped.Add([pscustomobject]@{
                Group = $r.groupName
                Unit = $r.unitName
                Reason = $res.Message
            })
        }
    }

    foreach ($r in $staticRecords) {
        $res = Insert-StaticRecordIntoMission -MissionText $missionText -Record $r
        if ($res.Success) {
            $missionText = $res.Text
            $inserted++
            Write-Info $res.Message
        } else {
            [void]$skipped.Add([pscustomobject]@{
                Group = $null
                Unit = $r.unitName
                Reason = $res.Message
            })
        }
    }
# --- Static object insertion ---

function Build-StaticEntryLua {
    param(
        [hashtable]$Record,
        [int]$EntryIndex
    )
    $typeName = Escape-LuaString ([string]$Record["typeName"])
    $unitName = Escape-LuaString ([string]$Record["unitName"])
    $x = [double]$Record["x"]
    $z = [double]$Record["z"]
    $heading = 0.0
    if ($Record.ContainsKey("heading")) { $heading = [double]$Record["heading"] }
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $xStr = $x.ToString("0.###", $inv)
    $zStr = $z.ToString("0.###", $inv)
    $hStr = $heading.ToString("0.######", $inv)
    return @"
        [$EntryIndex] =
        {
            ["type"] = "$typeName",
            ["unitId"] = 0,
            ["y"] = $zStr,
            ["x"] = $xStr,
            ["name"] = "$unitName",
            ["heading"] = $hStr,
        },
"@
}

function Insert-StaticRecordIntoMission {
    param(
        [string]$MissionText,
        [hashtable]$Record
    )
    $countryName = [string]$Record["countryName"]
    if ([string]::IsNullOrWhiteSpace($countryName)) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Missing countryName" }
    }
    $sideName = Resolve-SideName -Record $Record
    $coalitionRange = Find-KeyTableRange -Text $MissionText -Key "coalition" -SearchStart 0 -SearchEnd ($MissionText.Length - 1)
    if (-not $coalitionRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Mission missing coalition table" }
    }
    $sideRange = Find-KeyTableRange -Text $MissionText -Key $sideName -SearchStart $coalitionRange.Start -SearchEnd $coalitionRange.End
    if (-not $sideRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Mission missing side '$sideName'" }
    }
    $countryRange = Find-KeyTableRange -Text $MissionText -Key "country" -SearchStart $sideRange.Start -SearchEnd $sideRange.End
    if (-not $countryRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Mission missing country table for side '$sideName'" }
    }
    $countryEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $countryRange.Start -TableEnd $countryRange.End
    $targetCountry = $null
    $countryPattern = '(?m)\bname\s*=\s*["'']{0}["'']' -f ([Regex]::Escape($countryName))
    foreach ($entry in $countryEntries) {
        if ($entry.Text -match $countryPattern) {
            $targetCountry = $entry
            break
        }
    }
    if (-not $targetCountry) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Country '$countryName' not found under side '$sideName'" }
    }
    $staticResult = Ensure-KeyTable -Text $MissionText -ParentStart $targetCountry.Start -ParentEnd $targetCountry.End -Key "static" -TableInitializer "[\"static\"] = { [\"group\"] = {} },"
    $MissionText = $staticResult.Text
    # Refetch after mutation
    $coalitionRange = Find-KeyTableRange -Text $MissionText -Key "coalition" -SearchStart 0 -SearchEnd ($MissionText.Length - 1)
    $sideRange = Find-KeyTableRange -Text $MissionText -Key $sideName -SearchStart $coalitionRange.Start -SearchEnd $coalitionRange.End
    $countryRange = Find-KeyTableRange -Text $MissionText -Key "country" -SearchStart $sideRange.Start -SearchEnd $sideRange.End
    $countryEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $countryRange.Start -TableEnd $countryRange.End
    $targetCountry = $null
    foreach ($entry in $countryEntries) {
        if ($entry.Text -match $countryPattern) {
            $targetCountry = $entry
            break
        }
    }
    $staticRange = Find-KeyTableRange -Text $MissionText -Key "static" -SearchStart $targetCountry.Start -SearchEnd $targetCountry.End
    if (-not $staticRange) {
        return [pscustomobject]@{ Success = $false; Text = $MissionText; Message = "Static table lookup failed for '$countryName'" }
    }
    $groupResult = Ensure-KeyTable -Text $MissionText -ParentStart $staticRange.Start -ParentEnd $staticRange.End -Key "group" -TableInitializer "[\"group\"] = {}"
    $MissionText = $groupResult.Text
    # Refresh all relevant ranges after mutation
    $coalitionRange = Find-KeyTableRange -Text $MissionText -Key "coalition" -SearchStart 0 -SearchEnd ($MissionText.Length - 1)
    $sideRange = Find-KeyTableRange -Text $MissionText -Key $sideName -SearchStart $coalitionRange.Start -SearchEnd $coalitionRange.End
    $countryRange = Find-KeyTableRange -Text $MissionText -Key "country" -SearchStart $sideRange.Start -SearchEnd $sideRange.End
    $countryEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $countryRange.Start -TableEnd $countryRange.End
    $targetCountry = $null
    foreach ($entry in $countryEntries) {
        if ($entry.Text -match $countryPattern) {
            $targetCountry = $entry
            break
        }
    }
    $staticRange = Find-KeyTableRange -Text $MissionText -Key "static" -SearchStart $targetCountry.Start -SearchEnd $targetCountry.End
    $groupRange = Find-KeyTableRange -Text $MissionText -Key "group" -SearchStart $staticRange.Start -SearchEnd $staticRange.End
    $groupEntries = Get-TopLevelArrayEntries -Text $MissionText -TableStart $groupRange.Start -TableEnd $groupRange.End
    $nextIndex = Get-NextArrayIndex -Entries $groupEntries
    $entryLua = Build-StaticEntryLua -Record $Record -EntryIndex $nextIndex
    $insertAt = $groupRange.End
    $MissionText = $MissionText.Substring(0, $insertAt) + "`n$entryLua" + $MissionText.Substring($insertAt)
    return [pscustomobject]@{
        Success = $true
        Text = $MissionText
        Message = "Inserted static $($Record.unitName) into $sideName/$countryName"
    }
}

    [System.IO.File]::WriteAllText($missionPath, $missionText, [System.Text.UTF8Encoding]::new($false))

    if (Test-Path $outputFull) {
        Remove-Item -LiteralPath $outputFull -Force
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory($tempRoot, $outputFull, [System.IO.Compression.CompressionLevel]::Optimal, $false)

    Write-Info "Reintegration complete. Output: $outputFull"
    Write-Info "Inserted groups: $inserted"
    Write-Info "Skipped records: $($skipped.Count)"

    if ($skipped.Count -gt 0) {
        foreach ($s in $skipped) {
            Write-Info ("SKIP {0}/{1}: {2}" -f $s.Group, $s.Unit, $s.Reason)
        }
    }
}
finally {
    if (-not $KeepTemp -and (Test-Path $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
    elseif (Test-Path $tempRoot) {
        Write-Info "Kept temp folder: $tempRoot"
    }
}
12