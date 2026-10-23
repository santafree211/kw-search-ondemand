<#
.SYNOPSIS
    tools/sheet_commit_site.ps1
    Responsibility: Safely commit a verified site and its winning keywords to the spreadsheet while maintaining 50:25:25.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

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

    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
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
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

$expandedKws = @()
foreach ($kw in $WinningKws) {
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
. "$PSScriptRoot\..\workflow\scripts\store_api_query.ps1"
. "$PSScriptRoot\..\workflow\scripts\serpapi_client.ps1"
. "$PSScriptRoot\..\workflow\scripts\serpapi_evaluator.ps1"

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

    # Priority 1: Google Real SERP Evidence (SerpApi)
    $googleStored = Get-SerpApiStoredResult -Keyword $cleanKw
    if ($googleStored.Found -and $googleStored.OrganicResults) {
        $personalMap = Get-KnownPersonalBlogDomainMap
        $gEval = Evaluate-SerpApiResults -Keyword $cleanKw -OrganicResults $googleStored.OrganicResults -Gender $profile.Gender -KnownPersonalBlogMap $personalMap
        if ($gEval.IsStarLost -or $gEval.StarCount -le 0) {
            throw "Google Real-SERP Gate Violation for '$cleanKw': Google real-time SERP yields 0 weak seats (dominated by corporate/enterprise sites). Aborting commit."
        }
        $gMatch = ($gEval.StarCount -eq $kwStars) -or ($kwStars -ge 3 -and $gEval.StarCount -ge 3)
        if (-not $gMatch) {
            throw "Google Real-SERP Star Mismatch for '$cleanKw': Claimed $kwStars stars, but Google real-time SERP yields $($gEval.StarCount) weak seats ($($gEval.PersonalBlogSeats) personal + $($gEval.WeakUgcSeats) UGC). Aborting commit."
        }
    } else {
        # Priority 2: Ubersuggest Raw SERP Archive
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

# Deduplicate incoming WinningKws against existing sheet keywords
$dedupedWinningKws = @()
foreach ($wk in $WinningKws) {
    $clean = $wk -replace "^\s*[\u2605\u2606]+", ""
    $clean = ($clean -replace $parenPattern, "").Trim()
    $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $norm = (($tokens | Sort-Object) -join " ").ToLower()
    if ($existingTokenMap.ContainsKey($norm)) {
        Write-Warning "Commit guard: Rejecting duplicate keyword '$wk' (already registered as '$($existingTokenMap[$norm])')."
    } else {
        $dedupedWinningKws += $wk
        $existingTokenMap[$norm] = $wk
    }
}

if ($dedupedWinningKws.Count -eq 0) {
    throw "Cannot commit: All proposed winning keywords already exist in the spreadsheet."
}
$WinningKws = $dedupedWinningKws

# 3. Ratio check & allocation (Intelligent soft-guidance, never blocking qualified commits)
if ([string]::IsNullOrWhiteSpace($stockPath)) {
    $stockPath = $profile.StockPath
}
$alloc = Get-PortfolioAllocation -CurrentKws $currentKws -NewKws $WinningKws -StockPath $stockPath

$commitKws = @()
if ($alloc.CanCommit -and $alloc.CommitKeywords.Count -gt 0) {
    $commitKws = @($alloc.CommitKeywords)
} else {
    Write-Output "  [Golden Ratio Guard] Site '$SiteName' incoming keywords cannot be directly committed without violating 50:25:25 golden ratio."
    Write-Output "  -> Shelving all $($WinningKws.Count) incoming keywords to待機ストック ($stockPath) to preserve sheet quality."
    $existingShelved = @()
    if (Test-Path $stockPath) {
        try {
            $parsedStock = [System.IO.File]::ReadAllText($stockPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($parsedStock) { $existingShelved = @($parsedStock) }
        } catch {}
    }
    foreach ($w in $WinningKws) {
        if (-not ($existingShelved -contains $w)) { $existingShelved += $w }
    }
    $newShelvedJson = $existingShelved | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($stockPath, $newShelvedJson, [System.Text.UTF8Encoding]::new($false))
    return [PSCustomObject]@{
        Status = "Shelved_Due_To_Golden_Ratio"
        SiteName = $SiteName
        CommittedKws = @()
        ShelvedKws = $existingShelved
        Reason = "Preserving 50:25:25 Golden Ratio"
    }
}

if ($commitKws.Count -eq 0) {
    Write-Warning "No valid winning keywords eligible to commit under golden ratio."
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
$starDisplay = Get-StarDisplayString -kws $commitKws

# Construct new row (25 columns):
# Col 0: Status, Col 1: GenreNo, Col 2: GenreName, Col 3: SiteName, Col 4: URL, Col 5: DA, Col 6-21: KW1-16, Col 22: Stars, Col 23: Date, Col 24: Note
$newRow = @(
    $statusText,
    $GenreNumber,
    $GenreName,
    $SiteName,
    $Url,
    $Da
)
foreach ($k in $commitKws) { $newRow += $k }
while ($newRow.Count -lt 22) { $newRow += "" }
$newRow += $starDisplay
$newRow += $surveyDateFormatted
$newRow += ""

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
    Write-Host "Commit guard: Site domain '$targetDomain' already exists at Row $($existingSiteRowIndex + 2). Automatically merging keywords into existing row."
    $targetRow = [System.Collections.ArrayList]::new($existingRows[$existingSiteRowIndex])
    while ($targetRow.Count -lt 25) {
        [void]$targetRow.Add("")
    }

    $rowKws = [System.Collections.Generic.List[string]]::new()
    $kwStart = $kwStartCol
    $kwMax = $kwStartCol + 15

    for ($c = $kwStart; $c -le $kwMax; $c++) {
        $v = [string]$targetRow[$c]
        if (-not [string]::IsNullOrWhiteSpace($v)) {
            $rowKws.Add($v.Trim())
        }
    }

    $nextCol = $kwStart + $rowKws.Count
    foreach ($ck in $commitKws) {
        if (-not $rowKws.Contains($ck) -and $nextCol -le $kwMax) {
            $targetRow[$nextCol] = $ck
            $rowKws.Add($ck)
            $nextCol++
        }
    }

    # Update star count display and preserve original registration date
    $targetRow[22] = Get-StarDisplayString -kws $rowKws
    if ([string]::IsNullOrWhiteSpace([string]$targetRow[23])) {
        $targetRow[23] = $surveyDateFormatted
    }

    $existingRows[$existingSiteRowIndex] = $targetRow
    $updatedRows = @(,$header) + @($existingRows)
} else {
    $updatedRows = @(,$header) + @($existingRows) + @(,$newRow)
}

# 5. Pre-validate
$eval = Test-NormalStateStandard -SheetRows $updatedRows -EnforceUniqueSites -AllowHealing
if (-not $eval.Passed) {
    $errs = $eval.Errors -join "; "
    throw "Pre-validation FAILED: $errs"
}

# 6. Atomic Write (if not dry-run)
$writeRes = $null
if (-not $DryRun) {
    $writeRes = Update-SheetAtomic -Rows $updatedRows -SheetId $SpreadsheetId -AllowHealing
    # Save updated shelved stock safely
    $stockList = if ($alloc.ShelvedKeywords) { @($alloc.ShelvedKeywords) } else { @() }
    $newShelvedJson = $stockList | ConvertTo-Json -Depth 5
    if ([string]::IsNullOrWhiteSpace($newShelvedJson)) { $newShelvedJson = "[]" }
    [System.IO.File]::WriteAllText($stockPath, $newShelvedJson, [System.Text.UTF8Encoding]::new($false))
}

[PSCustomObject]@{
    Status = if ($DryRun) { "DryRun_Passed" } else { "Committed" }
    SiteName = $SiteName
    CommittedKws = $commitKws
    ShelvedKws = $alloc.ShelvedKeywords
    TotalKeywords = $alloc.TotalKeywordsAfter
    ResultingRatio = $alloc.ResultingRatio
    UpdatedCells = if ($writeRes) { $writeRes.UpdatedCells } else { 0 }
} | ConvertTo-Json -Depth 5
