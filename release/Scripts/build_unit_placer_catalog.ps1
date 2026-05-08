param(
	[string]$RepoRoot = "C:\HELL\CODE\DCS-AccMod",
	[switch]$IncludeSavedGamesMods = $true,
	[string]$SavedGamesRoot,
	[string]$SavedGamesProfile = "DCS",
	[int]$MaxSavedGamesFiles = 8000,
	[int]$MaxLuaFileSizeKB = 512
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SavedGamesRoot)) {
	$SavedGamesRoot = Join-Path $env:USERPROFILE (Join-Path 'Saved Games' $SavedGamesProfile)
}

$countriesDir = Join-Path $RepoRoot 'dcs-lua-datamine\_G\db\Countries'
$outFile = Join-Path $RepoRoot 'Mods\Services\DCS-AccWidg\Scripts\UnitPlacerCatalogDB.lua'

function Count-Char([string]$text, [char]$needle) {
	if ([string]::IsNullOrEmpty($text)) {
		return 0
	}

	return ($text.ToCharArray() | Where-Object { $_ -eq $needle }).Count
}

function Escape-Lua([string]$value) {
	if ($null -eq $value) {
		return ''
	}

	return $value.Replace('\', '\\').Replace('"', '\"')
}

function Get-FirstTagValue([string]$text) {
	if ([string]::IsNullOrEmpty($text)) {
		return $null
	}

	$tagsBlockMatch = [regex]::Match($text, '(?s)\btags\s*=\s*\{(.*?)\}')
	if (-not $tagsBlockMatch.Success) {
		return $null
	}

	$tagValues = New-Object System.Collections.ArrayList
	foreach ($tagMatch in [regex]::Matches($tagsBlockMatch.Groups[1].Value, '"([^"]+)"')) {
		$tagValue = $tagMatch.Groups[1].Value
		if (-not [string]::IsNullOrWhiteSpace($tagValue)) {
			[void]$tagValues.Add($tagValue)
		}
	}

	if ($tagValues.Count -eq 0) {
		return $null
	}

	return $tagValues
}

function Get-SubCategoryFromTags([System.Collections.ArrayList]$tags, [string]$categoryName, [string]$fallbackSubCategory) {
	if ($null -eq $tags -or $tags.Count -eq 0) {
		return $fallbackSubCategory
	}

	$genericTags = @{
		'All' = $true
		'Ground Units' = $true
		'Ground Units Non Airdefence' = $true
		'Armed ground units' = $true
		'Vehicles' = $true
		'Ground vehicles' = $true
		'Armed vehicles' = $true
	}

	$normalizedCategory = ''
	if (-not [string]::IsNullOrEmpty($categoryName)) {
		$normalizedCategory = $categoryName.ToLowerInvariant()
	}
	foreach ($tag in $tags) {
		$normalizedTag = $tag.ToLowerInvariant()
		if ($normalizedTag -ne $normalizedCategory -and -not $genericTags.ContainsKey($tag)) {
			return $tag
		}
	}

	return $fallbackSubCategory
}

function New-MetaMap($dirPath, $defaultCategory, $defaultSubCategory, $kind, $groupCategory) {
	$map = @{}
	if (-not (Test-Path $dirPath)) {
		return $map
	}

	Get-ChildItem -Path $dirPath -Filter '*.lua' | ForEach-Object {
		$typeName = $_.BaseName
		$text = Get-Content -Raw -Path $_.FullName
		$displayName = $typeName

		foreach ($pattern in @(
			'(?m)^\s*username\s*=\s*"([^"]+)"',
			'(?m)^\s*DisplayName\s*=\s*"([^"]+)"',
			'(?m)^\s*Name\s*=\s*"([^"]+)"',
			'(?m)^\s*type\s*=\s*"([^"]+)"'
		)) {
			$match = [regex]::Match($text, $pattern)
			if ($match.Success) {
				$displayName = $match.Groups[1].Value
				break
			}
		}

		$categoryName = $defaultCategory
		$categoryMatch = [regex]::Match($text, '(?m)^\s*category\s*=\s*"([^"]+)"')
		if ($categoryMatch.Success) {
			$categoryName = $categoryMatch.Groups[1].Value
		}

		$subCategoryName = $defaultSubCategory
		$tags = Get-FirstTagValue $text
		$subCategoryName = Get-SubCategoryFromTags $tags $categoryName $defaultSubCategory

		$map[$typeName] = @{
			displayName = $displayName
			categoryName = $categoryName
			subCategoryName = $subCategoryName
			kind = $kind
			groupCategory = $groupCategory
		}
	}

	return $map
}

function Get-CountryNameMap($countryNames) {
	$map = @{}
	foreach ($countryName in $countryNames) {
		$normalized = ("" + $countryName).ToUpperInvariant()
		$normalized = $normalized -replace '[^A-Z0-9]', ''
		if (-not [string]::IsNullOrEmpty($normalized)) {
			$map[$normalized] = $countryName
		}
	}
	return $map
}

function Get-CountriesFromText([string]$text, [hashtable]$countryNameMap) {
	$result = New-Object System.Collections.ArrayList
	if ([string]::IsNullOrEmpty($text)) {
		return $result
	}

	$countriesBlockMatch = [regex]::Match($text, '(?s)\bCountries\s*=\s*\{(.*?)\}')
	if (-not $countriesBlockMatch.Success) {
		return $result
	}

	foreach ($countryMatch in [regex]::Matches($countriesBlockMatch.Groups[1].Value, '"([^"]+)"')) {
		$token = $countryMatch.Groups[1].Value
		$normalized = ("" + $token).ToUpperInvariant()
		$normalized = $normalized -replace '[^A-Z0-9]', ''
		if ($countryNameMap.ContainsKey($normalized)) {
			$resolved = $countryNameMap[$normalized]
			if (-not $result.Contains($resolved)) {
				[void]$result.Add($resolved)
			}
		}
	}

	return $result
}

function Is-GroundLikeUnit([string]$text, [string]$categoryName) {
	if ([string]::IsNullOrEmpty($text)) {
		return $false
	}

	if ([regex]::IsMatch($text, '(?i)Ground Units|Ground vehicles|Armed ground units|Air Defence|Armor|Artillery|Infantry carriers|SAM')) {
		return $true
	}

	if (-not [string]::IsNullOrEmpty($categoryName)) {
		$normalized = $categoryName.ToLowerInvariant()
		if ($normalized -in @('armor', 'air defence', 'artillery', 'infantry', 'fortification', 'unarmed', 'carriage', 'cargo', 'ground', 'vehicles')) {
			return $true
		}
	}

	return $false
}

function Add-EntryToCatalog([hashtable]$catalog, [string]$countryName, [string]$categoryName, [string]$subCategoryName, [hashtable]$entry) {
	if (-not $catalog.ContainsKey($countryName)) {
		$catalog[$countryName] = @{}
	}
	if (-not $catalog[$countryName].ContainsKey($categoryName)) {
		$catalog[$countryName][$categoryName] = @{}
	}
	if (-not $catalog[$countryName][$categoryName].ContainsKey($subCategoryName)) {
		$catalog[$countryName][$categoryName][$subCategoryName] = New-Object System.Collections.ArrayList
	}

	[void]$catalog[$countryName][$categoryName][$subCategoryName].Add($entry)
}

function Add-SavedGamesModEntries(
	[hashtable]$catalog,
	[string]$savedGamesRoot,
	[System.Collections.ArrayList]$baseCountryNames,
	[hashtable]$countryNameMap,
	[int]$maxSavedGamesFiles,
	[int]$maxLuaFileSizeKB
) {
	$modsRoot = Join-Path $savedGamesRoot 'Mods'
	if (-not (Test-Path $modsRoot)) {
		Write-Verbose ('SAVED_GAMES_MODS_FOUND=0 (missing ' + $modsRoot + ')')
		return 0
	}

	$searchRoots = @(
		(Join-Path $modsRoot 'tech'),
		(Join-Path $modsRoot 'aircraft'),
		(Join-Path $modsRoot 'vehicles')
	)

	$seenByCountry = @{}
	foreach ($countryName in $baseCountryNames) {
		$seenByCountry[$countryName] = @{}
		if (-not $catalog.ContainsKey($countryName)) {
			continue
		}

		foreach ($categoryName in $catalog[$countryName].Keys) {
			foreach ($subCategoryName in $catalog[$countryName][$categoryName].Keys) {
				foreach ($entry in $catalog[$countryName][$categoryName][$subCategoryName]) {
					$existingKey = (("" + $entry.kind) + '|' + ("" + $entry.typeName)).ToLowerInvariant()
					$seenByCountry[$countryName][$existingKey] = $true
				}
			}
		}
	}

	$added = 0
	$scanned = 0
	$oversizeSkipped = 0
	$candidateSkipped = 0
	$maxBytes = [Math]::Max(32, $maxLuaFileSizeKB) * 1024

	foreach ($searchRoot in $searchRoots) {
		if (-not (Test-Path $searchRoot)) {
			continue
		}

		$files = Get-ChildItem -Path $searchRoot -Recurse -Filter '*.lua' -File -ErrorAction SilentlyContinue
		foreach ($file in $files) {
			if ($scanned -ge $maxSavedGamesFiles) {
				Write-Verbose ('SAVED_GAMES_SCAN_LIMIT_REACHED=' + $maxSavedGamesFiles)
				Write-Verbose ('SAVED_GAMES_SCANNED=' + $scanned)
				Write-Verbose ('SAVED_GAMES_OVERSIZE_SKIPPED=' + $oversizeSkipped)
				Write-Verbose ('SAVED_GAMES_CANDIDATE_SKIPPED=' + $candidateSkipped)
				return $added
			}

			$filePath = $file.FullName
			$scanned++

			if (($scanned % 500) -eq 0) {
				Write-Verbose ('SAVED_GAMES_PROGRESS scanned=' + $scanned + ' added=' + $added)
			}

			if ($file.Length -gt $maxBytes) {
				$oversizeSkipped++
				continue
			}

			$pathHint = $filePath.ToLowerInvariant()
			if ($pathHint -notmatch 'database|db_|ground|units|vehicle|fortification|cargo|tech') {
				$candidateSkipped++
				continue
			}

			$text = Get-Content -Raw -Path $filePath

			$typeName = $null
			foreach ($typePattern in @(
				'(?m)^\s*type\s*=\s*"([^"]+)"',
				'(?m)^\s*Name\s*=\s*"([^"]+)"'
			)) {
				$typeMatch = [regex]::Match($text, $typePattern)
				if ($typeMatch.Success) {
					$typeName = $typeMatch.Groups[1].Value
					break
				}
			}

			if ([string]::IsNullOrWhiteSpace($typeName)) {
				continue
			}

			$displayName = $typeName
			foreach ($displayPattern in @(
				'(?m)^\s*username\s*=\s*"([^"]+)"',
				'(?m)^\s*DisplayName\s*=\s*"([^"]+)"',
				'(?m)^\s*Name\s*=\s*"([^"]+)"'
			)) {
				$displayMatch = [regex]::Match($text, $displayPattern)
				if ($displayMatch.Success) {
					$displayName = $displayMatch.Groups[1].Value
					break
				}
			}

			$categoryName = 'Ground'
			$categoryMatch = [regex]::Match($text, '(?m)^\s*category\s*=\s*"([^"]+)"')
			if ($categoryMatch.Success) {
				$categoryName = $categoryMatch.Groups[1].Value
			}

			$kind = 'group'
			$groupCategory = 'GROUND'
			$subCategoryFallback = 'Mod Unit'
			if ($pathHint -match '\\fortification') {
				$kind = 'static'
				$groupCategory = ''
				$categoryName = 'Statics'
				$subCategoryFallback = 'Fortification'
			} elseif ($pathHint -match '\\cargo') {
				$kind = 'static'
				$groupCategory = ''
				$categoryName = 'Statics'
				$subCategoryFallback = 'Cargo'
			}

			if ($kind -eq 'group' -and -not (Is-GroundLikeUnit $text $categoryName)) {
				continue
			}

			$tags = Get-FirstTagValue $text
			$subCategoryName = Get-SubCategoryFromTags $tags $categoryName $subCategoryFallback

			$targetCountries = Get-CountriesFromText $text $countryNameMap
			if ($targetCountries.Count -eq 0) {
				$targetCountries = $baseCountryNames
			}

			foreach ($countryName in $targetCountries) {
				if (-not $seenByCountry.ContainsKey($countryName)) {
					$seenByCountry[$countryName] = @{}
				}

				$dedupeKey = ($kind + '|' + $typeName).ToLowerInvariant()
				if ($seenByCountry[$countryName].ContainsKey($dedupeKey)) {
					continue
				}

				$entryId = "$countryName|$kind|$typeName"
				$entry = @{
					entryId = $entryId
					displayName = $displayName
					typeName = $typeName
					kind = $kind
					groupCategory = $groupCategory
				}

				Add-EntryToCatalog $catalog $countryName $categoryName $subCategoryName $entry
				$seenByCountry[$countryName][$dedupeKey] = $true
				$added++
			}
		}
	}

	Write-Verbose ('SAVED_GAMES_SCANNED=' + $scanned)
	Write-Verbose ('SAVED_GAMES_OVERSIZE_SKIPPED=' + $oversizeSkipped)
	Write-Verbose ('SAVED_GAMES_CANDIDATE_SKIPPED=' + $candidateSkipped)

	return $added
}

function Add-CountrySectionEntries($countryFile, $countryName, $sectionName, $metaMap, [hashtable]$catalog) {
	$lines = Get-Content -Path $countryFile
	$inSection = $false
	$depth = 0

	foreach ($line in $lines) {
		if (-not $inSection) {
			if ($line -match ('^\s*' + [regex]::Escape($sectionName) + '\s*=\s*\{')) {
				$inSection = $true
				$depth = (Count-Char $line '{') - (Count-Char $line '}')
			}
			continue
		}

		if ($line -match '^\s*Name\s*=\s*"([^"]+)"') {
			$typeName = $matches[1]
			if ($metaMap.ContainsKey($typeName)) {
				$meta = $metaMap[$typeName]

				if (-not $catalog[$countryName].ContainsKey($meta.categoryName)) {
					$catalog[$countryName][$meta.categoryName] = @{}
				}
				if (-not $catalog[$countryName][$meta.categoryName].ContainsKey($meta.subCategoryName)) {
					$catalog[$countryName][$meta.categoryName][$meta.subCategoryName] = New-Object System.Collections.ArrayList
				}

				$entryId = "$countryName|$($meta.kind)|$typeName"
				[void]$catalog[$countryName][$meta.categoryName][$meta.subCategoryName].Add(@{
					entryId = $entryId
					displayName = $meta.displayName
					typeName = $typeName
					kind = $meta.kind
					groupCategory = $meta.groupCategory
				})
			}
		}

		$depth += (Count-Char $line '{') - (Count-Char $line '}')
		if ($depth -le 0) {
			break
		}
	}
}

$carsMeta = New-MetaMap (Join-Path $RepoRoot 'dcs-lua-datamine\_G\db\Units\Cars\Car') 'Ground' 'Car' 'group' 'GROUND'
$fortificationMeta = New-MetaMap (Join-Path $RepoRoot 'dcs-lua-datamine\_G\db\Units\Fortifications\Fortification') 'Statics' 'Fortification' 'static' ''
$cargoMeta = New-MetaMap (Join-Path $RepoRoot 'dcs-lua-datamine\_G\db\Units\Cargos\Cargo') 'Statics' 'Cargo' 'static' ''

$catalog = @{}

Get-ChildItem -Path $countriesDir -Filter '*.lua' | ForEach-Object {
	$countryName = $_.BaseName
	$catalog[$countryName] = @{}

	Add-CountrySectionEntries $_.FullName $countryName 'Cars' $carsMeta $catalog
	Add-CountrySectionEntries $_.FullName $countryName 'Fortifications' $fortificationMeta $catalog
	Add-CountrySectionEntries $_.FullName $countryName 'Cargos' $cargoMeta $catalog
}

$baseCountryNames = New-Object System.Collections.ArrayList
foreach ($countryName in ($catalog.Keys | Sort-Object)) {
	[void]$baseCountryNames.Add($countryName)
}

$countryNameMap = Get-CountryNameMap $baseCountryNames
$savedGamesAddedCount = 0
if ($IncludeSavedGamesMods) {
	$savedGamesAddedCount = Add-SavedGamesModEntries $catalog $SavedGamesRoot $baseCountryNames $countryNameMap $MaxSavedGamesFiles $MaxLuaFileSizeKB
}

$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine('return {')
[void]$builder.AppendLine('    version = 2,')
[void]$builder.AppendLine('    generatedAt = "' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '",')
[void]$builder.AppendLine('    source = "dcs-lua-datamine' + ($(if ($IncludeSavedGamesMods) { '+saved-games-mods' } else { '' })) + '",')
[void]$builder.AppendLine('    countries = {')

foreach ($countryName in ($catalog.Keys | Sort-Object)) {
	[void]$builder.AppendLine('        ["' + (Escape-Lua $countryName) + '"] = {')
	[void]$builder.AppendLine('            categories = {')

	foreach ($categoryName in ($catalog[$countryName].Keys | Sort-Object)) {
		[void]$builder.AppendLine('                ["' + (Escape-Lua $categoryName) + '"] = {')

		foreach ($subCategoryName in ($catalog[$countryName][$categoryName].Keys | Sort-Object)) {
			[void]$builder.AppendLine('                    ["' + (Escape-Lua $subCategoryName) + '"] = {')
			$entries = $catalog[$countryName][$categoryName][$subCategoryName] | Sort-Object displayName, typeName

			foreach ($entry in $entries) {
				$entryLine = '                        { entryId = "' + (Escape-Lua $entry.entryId) + '"'
				$entryLine += ', displayName = "' + (Escape-Lua $entry.displayName) + '"'
				$entryLine += ', typeName = "' + (Escape-Lua $entry.typeName) + '"'
				$entryLine += ', kind = "' + (Escape-Lua $entry.kind) + '"'

				if ($entry.groupCategory) {
					$entryLine += ', groupCategory = "' + (Escape-Lua $entry.groupCategory) + '"'
				}

				$entryLine += ' },'
				[void]$builder.AppendLine($entryLine)
			}

			[void]$builder.AppendLine('                    },')
		}

		[void]$builder.AppendLine('                },')
	}

	[void]$builder.AppendLine('            },')
	[void]$builder.AppendLine('        },')
}

[void]$builder.AppendLine('    },')
[void]$builder.AppendLine('}')

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($outFile, $builder.ToString(), $utf8NoBom)

$entryCount = 0
foreach ($countryName in $catalog.Keys) {
	foreach ($categoryName in $catalog[$countryName].Keys) {
		foreach ($subCategoryName in $catalog[$countryName][$categoryName].Keys) {
			$entryCount += $catalog[$countryName][$categoryName][$subCategoryName].Count
		}
	}
}

Write-Output ('WROTE=' + $outFile)
Write-Output ('COUNTRIES=' + $catalog.Keys.Count)
Write-Output ('ENTRIES=' + $entryCount)
Write-Output ('SAVED_GAMES_ROOT=' + $SavedGamesRoot)
Write-Output ('SAVED_GAMES_ENTRIES=' + $savedGamesAddedCount)
