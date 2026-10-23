<#
.SYNOPSIS
    tools/sheet_commit_site.ps1
    Responsibility: Safely commit a verified site and its winning keywords to the spreadsheet while maintaining 50:25:25.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Mandatory=$false)]
    [string]$SiteJsonPath = "",

    [Parameter(Mandatory=$false)]
    [string]$SiteName = "",

    [Parameter(Mandatory=$false)]
    [string]$Url = "",

    [Parameter(Mandatory=$false)]
    [string]$SiteKey = "",

    [Parameter(Mandatory=$false)]
    [int]$Da = 0,

    [Parameter(Mandatory=$false)]
    [string]$OriginKw = "",

    [Parameter(Mandatory=$false)]
    [string[]]$WinningKws = @(),

    [Parameter(Mandatory=$false)]
    [string]$SpreadsheetId = "",

    [Parameter(Mandatory=$false)]
    [string]$Gender = "",

    [Parameter(Mandatory=$false)]
    [string]$SurveyDate = "",

    [Parameter(Mandatory=$false)]
    [string]$GenreNumber = "",

    [Parameter(Mandatory=$false)]
    [string]$GenreName = "",

    [Parameter(Mandatory=$false)]
    $DryRun = $false,

    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Stop"

$isDryRun = ($DryRun -eq $true -or "$DryRun" -match "^(?i:true|1)$" -or ($DryRun -is [System.Management.Automation.SwitchParameter] -and $DryRun.IsPresent))

$expandedKws = @()
$rawKwList = @($WinningKws) + @($ExtraArgs)
foreach ($kw in $rawKwList) {
    if (-not [string]::IsNullOrWhiteSpace($kw)) {
        $parts = $kw -split ",\s*"
        foreach ($p in $parts) {
            $trimmed = $p.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                $expandedKws += $trimmed
            }
        }
    }
}
$WinningKws = $expandedKws

. "$PSScriptRoot\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_data_reader.ps1"
. "$PSScriptRoot\..\workflow\scripts\portfolio_ratio_balancer.ps1"
. "$PSScriptRoot\..\workflow\scripts\guard_normal_state.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_atomic_writer.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_date_tracker.ps1"
. "$PSScriptRoot\..\workflow\scripts\guard_check_gender_kw.ps1"
. "$PSScriptRoot\..\workflow\scripts\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\..\workflow\scripts\guard_check_entertainment_kw.ps1"
. "$PSScriptRoot\..\workflow\scripts\eval_star_calculator.ps1"
. "$PSScriptRoot\..\workflow\scripts\eval_star_calculator_male.ps1"
. "$PSScriptRoot\..\workflow\scripts\eval_weak_competitor_rule.ps1"
. "$PSScriptRoot\..\workflow\scripts\eval_weak_competitor_male_rule.ps1"
. "$PSScriptRoot\..\workflow\scripts\store_api_query.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_cross_gender_guard.ps1"

$profile = Resolve-SheetProfile -SpreadsheetId $SpreadsheetId -Gender $Gender
$SpreadsheetId = $profile.SpreadsheetId
$stockPath = $profile.StockPath

# 1. Parse site input
if (-not [string]::IsNullOrWhiteSpace($SiteJsonPath) -and (Test-Path $SiteJsonPath)) {
    $text = [System.IO.File]::ReadAllText($SiteJsonPath, [System.Text.Encoding]::UTF8)
    $obj = $text | ConvertFrom-Json
    if ($obj.SiteName) { $SiteName = $obj.SiteName }
    if ($obj.Url) { $Url = $obj.Url }
    if ($obj.SiteKey) { $SiteKey = $obj.SiteKey }
    if ($obj.Da) { $Da = [int]$obj.Da }
    if ($obj.OriginKw) { $OriginKw = $obj.OriginKw }
    if ($obj.WinningKws) { $WinningKws = @($obj.WinningKws) }
    if ($obj.GenreNumber) { $GenreNumber = $obj.GenreNumber }
    if ($obj.GenreName) { $GenreName = $obj.GenreName }
}

if ([string]::IsNullOrWhiteSpace($SiteName) -or $WinningKws.Count -eq 0) {
    throw "SiteName and at least 1 WinningKw are required."
}

# 1.1 DA Range Gate (Rule 3: Personal blogs DA 1-9 only)
if ($Da -lt 1 -or $Da -gt 9) {
    throw "DA Range Violation: Only personal blogs with DA 1-9 are eligible (Received DA: $Da). Aborting commit."
}

# 1.2 UGC/CGM Exclusion Gate (Rule 3: Cannot register UGC platform as a row subject)
$checkDomain = ""
if (-not [string]::IsNullOrWhiteSpace($Url)) {
    try {
        $uUri = [System.Uri]$Url
        $checkDomain = $uUri.Host.ToLower().Trim()
        if ($checkDomain.StartsWith("www.")) { $checkDomain = $checkDomain.Substring(4) }
    } catch {
        $checkDomain = $Url.ToLower().Trim()
    }
}
$isUgc = if ($profile.Gender -eq "male") {
    Test-WeakCompetitorMale -Domain $checkDomain -Url $Url
} else {
    Test-WeakCompetitor -Domain $checkDomain -Url $Url
}
if ($isUgc.IsWeakCompetitor) {
    throw "UGC Platform Row Subject Violation: Cannot register weak UGC/CGM competitor ('$Url', Category: $($isUgc.CategoryName)) as a site row subject. Only pure personal blogs (DA 1-9) are eligible. Aborting commit."
}

# 1.5 Gender Guard Gate
foreach ($wKw in $WinningKws) {
    $gCheck = Test-KeywordGenderEligibility -Gender $profile.Gender -Keyword $wKw
    if (-not $gCheck.IsAllowed) {
        throw "Gender Guard Violation: $($gCheck.Reason). Aborting commit."
    }
}

# 1.6 YMYL Guard Gate (Physical Block)
if (-not [string]::IsNullOrWhiteSpace($OriginKw)) {
    $yCheckOrigin = Test-KeywordYmylEligibility -Keyword $OriginKw
    if ($yCheckOrigin.IsYmyl) {
        throw "YMYL Guard Violation (OriginKw): $($yCheckOrigin.Reason). Aborting commit."
    }
}
foreach ($wKw in $WinningKws) {
    $yCheck = Test-KeywordYmylEligibility -Keyword $wKw
    if ($yCheck.IsYmyl) {
        throw "YMYL Guard Violation (WinningKw): $($yCheck.Reason). Aborting commit."
    }
}

# 1.7 Entertainment & Fiction Guard Gate (Physical Block)
if (-not [string]::IsNullOrWhiteSpace($OriginKw)) {
    $entCheckOrigin = Test-KeywordEntertainmentEligibility -Keyword $OriginKw
    if ($entCheckOrigin.IsEntertainment) {
        throw "Entertainment Guard Violation (OriginKw): $($entCheckOrigin.Reason). Aborting commit."
    }
}
foreach ($wKw in $WinningKws) {
    $entCheck = Test-KeywordEntertainmentEligibility -Keyword $wKw
    if ($entCheck.IsEntertainment) {
        throw "Entertainment Guard Violation (WinningKw): $($entCheck.Reason). Aborting commit."
    }
}

# 1.8 SERP Star Reconciliation Pre-check Gate (Physical Block)
# Verify that stars in winning keywords match actual raw SERP cache top 10 weak seats
$isFemale = ($profile.Gender -eq "female")
$starChar = [char]0x2606
$parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

foreach ($wKw in $WinningKws) {
    $tKw = ([string]$wKw).Trim()
    $kwStars = 0
    while ($kwStars -lt $tKw.Length -and $tKw[$kwStars] -eq $starChar) { $kwStars++ }
    $cleanKw = $tKw.Substring($kwStars).Trim()
    $vol = 0
    if ($cleanKw -match $parenPattern) {
        $vol = [int]$matches[1]
        $cleanKw = ($cleanKw -replace $parenPattern, "").Trim()
    }

    $arch = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $cleanKw
    if ($arch -and $arch.Data) {
        $serpEntries = $null
        if ($arch.Data.serpEntries) { $serpEntries = $arch.Data.serpEntries }
        elseif ($arch.Data.serp_table) { $serpEntries = $arch.Data.serp_table }
        elseif ($arch.Data.result -and $arch.Data.result.serp_table) { $serpEntries = $arch.Data.result.serp_table }

        if ($serpEntries) {
            $starEval = if ($isFemale) {
                Get-StrictStarEvaluation -Keyword $cleanKw -SearchVolume $vol -SerpEntries $serpEntries
            } else {
                Get-StrictStarEvaluationMale -Keyword $cleanKw -SearchVolume $vol -SerpEntries $serpEntries
            }

            $calcStars = $starEval.StarCount
            $starMatch = ($calcStars -eq $kwStars) -or ($kwStars -ge 3 -and $calcStars -ge 3)
            if (-not $starMatch) {
                throw "SERP Star Reconciliation Violation for '$cleanKw': Claimed $kwStars stars, but Raw SERP top 10 yields $calcStars weak seats ($($starEval.PureLowDaCount) personal + $($starEval.WeakUgcCount) UGC). Aborting commit."
            }
        }
    }
}

# 2. Read existing sheet
$current = Read-SheetData -SheetId $SpreadsheetId
$header = $current.Header
$existingRows = $current.Rows

$surveyDateFormatted = Format-SurveyDate -RawDate $SurveyDate

$kwStartCol = 6
for ($i = 0; $i -lt $header.Count; $i++) {
    $h = [string]$header[$i]
    if ($h.Contains("KW1")) {
        $kwStartCol = $i
        break
    }
}

$currentKws = @()
$existingTokenMap = @{}
$starChar = [char]0x2606
$parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

foreach ($r in $existingRows) {
    for ($c = $kwStartCol; $c -lt [Math]::Min($r.Count, ($kwStartCol + 16)); $c++) {
        $val = [string]$r[$c]
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $lines = $val -split "`r?`n"
            foreach ($l in $lines) {
                $t = $l.Trim()
                if ($t.StartsWith($starChar)) {
                    $currentKws += $t
                    $clean = $t -replace "^\s*[\u2605\u2606]+", ""
                    $clean = ($clean -replace $parenPattern, "").Trim()
                    $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $norm = (($tokens | Sort-Object) -join " ").ToLower()
                    if (-not [string]::IsNullOrWhiteSpace($norm)) {
                        $existingTokenMap[$norm] = $t
                    }
                }
            }
        }
    }
}

# Deduplicate and canonicalize incoming WinningKws against existing sheet keywords
$dedupedWinningKws = @()
foreach ($wk in $WinningKws) {
    $tWk = ([string]$wk).Trim()
    $kwStars = 0
    while ($kwStars -lt $tWk.Length -and $tWk[$kwStars] -eq $starChar) { $kwStars++ }
    $clean = $tWk.Substring($kwStars).Trim()
    $vol = 0
    if ($clean -match $parenPattern) {
        $vol = [int]$matches[1]
        $clean = ($clean -replace $parenPattern, "").Trim()
    }
    # Enforce canonical format: ☆☆☆KW(Vol)
    $starPrefix = [string]::new($starChar, $kwStars)
    $canonicalWk = if ($vol -gt 0) { "$starPrefix$clean($vol)" } else { $tWk }

    $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $norm = (($tokens | Sort-Object) -join " ").ToLower()
    if ($existingTokenMap.ContainsKey($norm)) {
        Write-Warning "Commit guard: Rejecting duplicate keyword '$canonicalWk' (already registered as '$($existingTokenMap[$norm])')."
    } else {
        # Cross-Gender Barrier 2: Reject if keyword exists in opposite sheet
        $crossCheck = Test-IsCrossGenderDuplicate -Keyword $clean -CurrentGender $profile.Gender
        if ($crossCheck.IsDuplicate) {
            Write-Warning "Cross-Gender Commit Guard: Rejecting duplicate '$canonicalWk' (already registered in $($crossCheck.OppositeGender) sheet as '$($crossCheck.ExistingKeyword)')."
        } else {
            $dedupedWinningKws += $canonicalWk
            $existingTokenMap[$norm] = $canonicalWk
        }
    }
}

if ($dedupedWinningKws.Count -eq 0) {
    throw "Cannot commit: All proposed winning keywords already exist in the spreadsheet."
}
$WinningKws = $dedupedWinningKws

# 3. Ratio check & allocation (Strict Golden Ratio Standard: 50% Star3+, <=25% Star2, <=25% Star1)
if ([string]::IsNullOrWhiteSpace($stockPath)) {
    $stockPath = $profile.StockPath
}
$alloc = Get-PortfolioAllocation -CurrentKws $currentKws -NewKws $WinningKws -StockPath $stockPath

# Always persist updated shelved stock
if ($alloc.ShelvedKeywords -and $alloc.ShelvedKeywords.Count -gt 0) {
    $dir = Split-Path -Parent $stockPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($stockPath, ($alloc.ShelvedKeywords | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
}

if (-not $alloc.CanCommit -or $alloc.CommitKeywords.Count -eq 0) {
    Write-Warning "Golden Ratio Gate: Incoming keywords would violate 50:25:25 golden ratio (Star3+ >= 50%). Shelved $($WinningKws.Count) keywords to stock ($stockPath) until more Star3+ are discovered."
    return
}

$commitKws = @($alloc.CommitKeywords)

if ($commitKws.Count -eq 0) {
    Write-Warning "No valid winning keywords available to commit."
    return
}

# 4. Resolve Genre Number and Genre Name with Strict Semantic Matching
$catalogPath = Join-Path $PSScriptRoot "..\workflow\config\genre_catalog_$($profile.Gender).json"
$catalogGenres = @()
if (Test-Path $catalogPath) {
    try {
        $catJson = [System.IO.File]::ReadAllText($catalogPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        $catalogGenres = @($catJson.genres)
    } catch {}
}

$searchTarget = ("$SiteName " + ($commitKws -join " ")).ToLower()

# Helper function to test match between search target and a genre definition (Pure ASCII / Unicode escape safe)
function Test-GenreMatch($genreObj, $targetText) {
    if (-not $genreObj) { return $false }
    $gSeeds = @($genreObj.seeds)
    foreach ($sd in $gSeeds) {
        $sdLower = ([string]$sd).ToLower().Trim()
        if (-not [string]::IsNullOrWhiteSpace($sdLower) -and $targetText.Contains($sdLower)) {
            return $true
        }
    }
    $nakaguro = [char]0x30FB
    $splitPattern = "[" + $nakaguro + "\s\/\(\)]+"
    $gTokens = ([string]$genreObj.name) -split $splitPattern
    foreach ($gt in $gTokens) {
        $gtLower = $gt.ToLower().Trim()
        if ($gtLower.Length -ge 2 -and $targetText.Contains($gtLower)) {
            return $true
        }
    }
    return $false
}

# If GenreNumber was specified, resolve it from catalog
$matchedGenre = $null
if (-not [string]::IsNullOrWhiteSpace($GenreNumber)) {
    $cleanNum = $GenreNumber.Trim()
    $prefix = $profile.Gender.Substring(0,1).ToUpper()
    $specifiedGenre = $catalogGenres | Where-Object { 
        $_.id -eq $cleanNum -or 
        $_.id -eq "$prefix-$cleanNum" -or 
        $_.id -eq "$prefix-0$cleanNum" -or
        $_.name -eq $GenreName
    } | Select-Object -First 1
    if ($specifiedGenre) {
        $matchedGenre = $specifiedGenre
    }
}

# If not matched yet, search across all catalog genres semantically
if (-not $matchedGenre) {
    foreach ($g in $catalogGenres) {
        if (Test-GenreMatch -genreObj $g -targetText $searchTarget) {
            $matchedGenre = $g
            break
        }
    }
}

if ($matchedGenre) {
    $GenreNumber = $matchedGenre.id
    $GenreName = $matchedGenre.name
    Write-Output "Genre Resolved: [$GenreNumber] $GenreName"
} elseif (-not [string]::IsNullOrWhiteSpace($GenreName)) {
    Write-Output "Genre Preserved: [$GenreNumber] $GenreName"
} else {
    throw "Genre Resolution Failed: Keywords '$($commitKws -join ', ')' did not match any of the 50 genres in catalog. Refusing to blindly assign fallback genre. Aborting commit."
}

# Star display helper (e.g. ⭐️⭐️⭐️ (3) or ⭐️〜⭐️⭐️⭐️)
function Get-StarDisplayString($kws) {
    $starVals = @()
    $starChar = [char]0x2606
    foreach ($k in $kws) {
        $str = ([string]$k).Trim()
        $c = 0
        while ($c -lt $str.Length -and $str[$c] -eq $starChar) { $c++ }
        if ($c -gt 0) { $starVals += $c }
    }
    if ($starVals.Count -eq 0) { return [char]0x2B50 }
    $minS = ($starVals | Measure-Object -Minimum).Minimum
    $maxS = ($starVals | Measure-Object -Maximum).Maximum
    $starEmoji = [char]0x2B50
    $waveDash = [char]0x301C
    if ($minS -eq $maxS) {
        $emojis = [string]::new($starEmoji, $minS)
        return "$emojis ($minS)"
    } else {
        $eMin = [string]::new($starEmoji, $minS)
        $eMax = [string]::new($starEmoji, $maxS)
        return "$eMin$waveDash$eMax"
    }
}

$statusText = [System.Text.Encoding]::UTF8.GetString(@(0xF0,0x9F,0x9F,0xA2,0x20,0xE8,0xAA,0xBF,0xE6,0x9F,0xBB,0xE6,0xB8,0x88,0xE3,0x83,0xBB,0xE7,0x99,0xBB,0xE9,0x8C,0xB2,0xE5,0xAE,0x8C,0xE4,0xBA,0x86))

function Build-SiteRow {
    param(
        [string]$Status,
        [string]$GenreNo,
        [string]$GenreNm,
        [string]$SiteNm,
        [string]$SiteUrl,
        $SiteDa,
        [string[]]$Keywords,
        [string]$DateFormatted
    )
    $row = @(
        $Status,
        $GenreNo,
        $GenreNm,
        $SiteNm,
        $SiteUrl,
        $SiteDa
    )
    $kwsToPut = @()
    if ($Keywords) {
        $kwsToPut = @($Keywords | Select-Object -First 16)
    }
    foreach ($k in $kwsToPut) { $row += $k }
    while ($row.Count -lt 22) { $row += "" }
    $row += (Get-StarDisplayString -kws $kwsToPut)
    $row += $DateFormatted
    $row += ""
    return $row
}

# 4.5 Check if site already exists in spreadsheet to automatically merge into existing row
$targetDomain = ""
if (-not [string]::IsNullOrWhiteSpace($Url)) {
    try {
        $uri = [System.Uri]$Url
        $targetDomain = $uri.Host.ToLower().Trim()
        if ($targetDomain.StartsWith("www.")) { $targetDomain = $targetDomain.Substring(4) }
    } catch {
        $targetDomain = $Url.ToLower().Trim()
    }
}

$urlColIdx = 4
for ($i = 0; $i -lt $header.Count; $i++) {
    $h = [string]$header[$i]
    if ($h -match "URL" -or $h -match "代表URL") {
        $urlColIdx = $i
        break
    }
}

$existingSiteRowIndex = -1
if (-not [string]::IsNullOrWhiteSpace($targetDomain)) {
    for ($r = 0; $r -lt $existingRows.Count; $r++) {
        $rUrl = if ($existingRows[$r].Count -gt $urlColIdx) { ([string]$existingRows[$r][$urlColIdx]).Trim() } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($rUrl)) {
            $rDom = ""
            try {
                $rUri = [System.Uri]$rUrl
                $rDom = $rUri.Host.ToLower().Trim()
                if ($rDom.StartsWith("www.")) { $rDom = $rDom.Substring(4) }
            } catch {
                $rDom = $rUrl.ToLower().Trim()
            }
            if ($rDom -eq $targetDomain) {
                $existingSiteRowIndex = $r
                break
            }
        }
    }
}

if ($existingSiteRowIndex -ge 0) {
    Write-Host "Commit guard: Site domain '$targetDomain' already exists at Row $($existingSiteRowIndex + 2). Merging keywords with 16-KW limit per row."
    $rowsList = [System.Collections.Generic.List[object]]::new($existingRows)
    
    # Identify all consecutive rows for this domain
    $siteRowIndices = [System.Collections.Generic.List[int]]::new()
    $siteRowIndices.Add($existingSiteRowIndex)
    $chkIdx = $existingSiteRowIndex + 1
    while ($chkIdx -lt $rowsList.Count) {
        $cUrl = if ($rowsList[$chkIdx].Count -gt $urlColIdx) { ([string]$rowsList[$chkIdx][$urlColIdx]).Trim() } else { "" }
        $cDom = ""
        try {
            $cUri = [System.Uri]$cUrl
            $cDom = $cUri.Host.ToLower().Trim()
            if ($cDom.StartsWith("www.")) { $cDom = $cDom.Substring(4) }
        } catch { $cDom = $cUrl.ToLower().Trim() }
        if ($cDom -eq $targetDomain) {
            $siteRowIndices.Add($chkIdx)
            $chkIdx++
        } else {
            break
        }
    }

    # Collect existing keywords across all rows of this site
    $allExistingKws = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($rIdx in $siteRowIndices) {
        $rData = $rowsList[$rIdx]
        for ($c = $kwStartCol; $c -lt [Math]::Min($rData.Count, ($kwStartCol + 16)); $c++) {
            $v = [string]$rData[$c]
            if (-not [string]::IsNullOrWhiteSpace($v)) {
                [void]$allExistingKws.Add($v.Trim())
            }
        }
    }

    # Determine incoming keywords to add
    $toAdd = New-Object System.Collections.Generic.List[string]
    foreach ($ck in $commitKws) {
        if (-not $allExistingKws.Contains($ck)) {
            $toAdd.Add($ck)
        }
    }

    # Populate existing rows up to 16 keywords each
    foreach ($rIdx in $siteRowIndices) {
        if ($toAdd.Count -eq 0) { break }
        $rList = [System.Collections.ArrayList]@($rowsList[$rIdx])
        while ($rList.Count -lt 25) { [void]$rList.Add("") }
        
        $currentCount = 0
        for ($c = $kwStartCol; $c -le ($kwStartCol + 15); $c++) {
            if (-not [string]::IsNullOrWhiteSpace([string]$rList[$c])) { $currentCount++ }
        }

        $rowKws = New-Object System.Collections.Generic.List[string]
        for ($c = $kwStartCol; $c -le ($kwStartCol + 15); $c++) {
            $val = [string]$rList[$c]
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $rowKws.Add($val.Trim())
            } elseif ($toAdd.Count -gt 0) {
                $nxt = $toAdd[0]
                $toAdd.RemoveAt(0)
                $rList[$c] = $nxt
                $rowKws.Add($nxt)
            }
        }

        $rList[22] = Get-StarDisplayString -kws $rowKws
        if ([string]::IsNullOrWhiteSpace([string]$rList[23])) {
            $rList[23] = $surveyDateFormatted
        }
        $rowsList[$rIdx] = $rList
    }

    # If keywords remain, create and insert split continuation rows right after the last site row
    $insertPos = $siteRowIndices[$siteRowIndices.Count - 1] + 1
    $baseRow = $rowsList[$existingSiteRowIndex]
    $bStatus = if ($baseRow.Count -gt 0) { [string]$baseRow[0] } else { $statusText }
    $bGenreNo = if ($baseRow.Count -gt 1) { [string]$baseRow[1] } else { $GenreNumber }
    $bGenreNm = if ($baseRow.Count -gt 2) { [string]$baseRow[2] } else { $GenreName }
    $bSiteNm = if ($baseRow.Count -gt 3) { [string]$baseRow[3] } else { $SiteName }
    $bUrl = if ($baseRow.Count -gt 4) { [string]$baseRow[4] } else { $Url }
    $bDa = if ($baseRow.Count -gt 5) { $baseRow[5] } else { $Da }

    while ($toAdd.Count -gt 0) {
        $chunkSize = [Math]::Min(16, $toAdd.Count)
        $chunkKws = @()
        for ($k = 0; $k -lt $chunkSize; $k++) {
            $chunkKws += $toAdd[0]
            $toAdd.RemoveAt(0)
        }

        $splitRow = Build-SiteRow -Status $bStatus -GenreNo $bGenreNo -GenreNm $bGenreNm -SiteNm $bSiteNm -SiteUrl $bUrl -SiteDa $bDa -Keywords $chunkKws -DateFormatted $surveyDateFormatted
        $rowsList.Insert($insertPos, $splitRow)
        $insertPos++
    }

    $updatedRows = @(,$header) + @($rowsList)
} else {
    # New site: chunk keywords into groups of 16 and append split continuation rows if > 16
    $newRowsToAppend = @()
    $kList = @($commitKws)
    for ($i = 0; $i -lt $kList.Count; $i += 16) {
        $endIdx = [Math]::Min($i + 15, $kList.Count - 1)
        $chunkKws = @($kList[$i..$endIdx])
        $chunkRow = Build-SiteRow -Status $statusText -GenreNo $GenreNumber -GenreNm $GenreName -SiteNm $SiteName -SiteUrl $Url -SiteDa $Da -Keywords $chunkKws -DateFormatted $surveyDateFormatted
        $newRowsToAppend += ,$chunkRow
    }

    $updatedRows = @(,$header) + @($existingRows) + $newRowsToAppend
}

# 5. Pre-validate
$eval = Test-NormalStateStandard -SheetRows $updatedRows -EnforceUniqueSites -AllowHealing
if (-not $eval.Passed) {
    $errs = $eval.Errors -join "; "
    throw "Pre-validation FAILED: $errs"
}

# 6. Atomic Write (if not dry-run)
$writeRes = $null
if (-not $isDryRun) {
    $writeRes = Update-SheetAtomic -Rows $updatedRows -SheetId $SpreadsheetId -TargetSheetName $profile.TargetSheetName -AllowHealing
    # Save updated shelved stock safely
    $stockList = if ($alloc.ShelvedKeywords) { @($alloc.ShelvedKeywords) } else { @() }
    $newShelvedJson = $stockList | ConvertTo-Json -Depth 5
    if ([string]::IsNullOrWhiteSpace($newShelvedJson)) { $newShelvedJson = "[]" }
    [System.IO.File]::WriteAllText($stockPath, $newShelvedJson, [System.Text.Encoding]::UTF8)
}

[PSCustomObject]@{
    Status = if ($isDryRun) { "DryRun_Passed" } else { "Committed" }
    SiteName = $SiteName
    CommittedKws = $commitKws
    ShelvedKws = $alloc.ShelvedKeywords
    TotalKeywords = $alloc.TotalKeywordsAfter
    ResultingRatio = $alloc.ResultingRatio
    UpdatedCells = if ($writeRes) { $writeRes.UpdatedCells } else { 0 }
} | ConvertTo-Json -Depth 5
