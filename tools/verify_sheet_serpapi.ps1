<#
.SYNOPSIS
    tools/verify_sheet_serpapi.ps1
    Responsibility: Verify winning keywords in spreadsheets using Google SerpApi.
    Features:
      1. Daily 90-call hard limit to protect free tier.
      2. Re-evaluates Top 10 organic seats (Independent personal blogs DA 1-9 + Weak UGC).
      3. If stars become 0 -> Automatically deletes the keyword from the spreadsheet.
      4. Records SerpApi verification evidence in the remarks and date columns.
      5. Full support for -MockMode (allows testing without an active API key).
      6. Supports -DryRun (simulation without modifying spreadsheets).
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [int]$Limit = 7,

    [Parameter(Mandatory=$false)]
    [string]$ApiKey = "",

    [Parameter(Mandatory=$false)]
    [switch]$MockMode = $false,

    [Parameter(Mandatory=$false)]
    [int]$MinDays = 3,

    [Parameter(Mandatory=$false)]
    [switch]$Force = $false,

    [Parameter(Mandatory=$false)]
    [switch]$SyncCached = $false,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\sheet_atomic_writer.ps1"
. "$projectRoot\workflow\scripts\serpapi_client.ps1"
. "$projectRoot\workflow\scripts\serpapi_evaluator.ps1"
. "$projectRoot\workflow\scripts\guard_normal_state.ps1"

Write-Output "=========================================================="
Write-Output "=== SERPAPI SPREADSHEET STAR VERIFICATION & SYNC ==="
Write-Output "=========================================================="
Write-Output "Target Gender : $Gender"
Write-Output "Max Call Limit: $Limit (Daily: 7 / Monthly: 240)"
Write-Output "Sync Cached   : $SyncCached"
Write-Output "Mock Mode     : $MockMode"
Write-Output "DryRun Mode   : $DryRun"

# 1. Quota Pre-flight Check
$usage = Get-SerpApiDailyUsage -DailyLimit 7 -MonthlyLimit 240
Write-Output "Current Usage : $($usage.CallsToday) / $($usage.DailyLimit) calls today (Month: $($usage.CallsThisMonth) / $($usage.MonthlyLimit), Remaining: $($usage.RemainingCalls))"
if (-not $MockMode -and -not $SyncCached -and $usage.IsLimitReached) {
    if ($usage.IsDailyLimitReached) {
        Write-Warning "SerpApi daily quota of $($usage.DailyLimit) calls has already been reached for today."
    }
    if ($usage.IsMonthlyLimitReached) {
        Write-Warning "SerpApi monthly quota of $($usage.MonthlyLimit) calls has already been reached for this month."
    }
    Write-Output "Cannot make any new SerpApi calls. Exiting safely."
    return
}

# Determine effective call budget
$availableCalls = if ($SyncCached) { 100000 } elseif ($MockMode) { $Limit } else { [Math]::Min($Limit, $usage.RemainingCalls) }
Write-Output "Callable Budget: $availableCalls keywords can be verified in this run."

$gendersToProcess = if ($Gender -eq "both") { @("male", "female") } else { @($Gender) }
$totalVerified = 0
$totalDeleted = 0
$totalUpdated = 0
$totalUnchanged = 0
$totalSkipped = 0

$parenPattern = "[\(\uff08][0-9kKmM\.,\s]+[\)\uff09]$"
$starChar = [char]0x2606 # Empty star ☆
$starFull = [char]0x2605 # Full star ★

# UTF-8 encoded text helpers for PowerShell 5.1 compatibility
$tagSerpApiPrefix = [System.Text.Encoding]::UTF8.GetString(@(0x5B,0x53,0x65,0x72,0x70,0x41,0x70,0x69,0xE7,0xA2,0xBA,0xE8,0xAA,0x8D,0x3A,0x20)) # "[SerpApi確認: "
$statusLostAll    = [System.Text.Encoding]::UTF8.GetString(@(0x5B,0xE6,0x98,0x9F,0xE6,0xB6,0x88,0xE6,0xBB,0x85,0xE3,0x83,0xBB,0xE5,0x85,0xA8,0xE6,0xBB,0x85,0x5D)) # "[星消滅・全滅]"
$strLatestStar    = [System.Text.Encoding]::UTF8.GetString(@(0xE6,0x9C,0x80,0xE6,0x96,0xB0)) # "最新"

foreach ($g in $gendersToProcess) {
    if ($availableCalls -le 0) { break }

    $profile = Resolve-SheetProfile -Gender $g
    Write-Output "`n----------------------------------------------------------"
    Write-Output "Processing Profile: $g ($($profile.SheetTitle))"
    Write-Output "Spreadsheet ID    : $($profile.SpreadsheetId)"
    Write-Output "----------------------------------------------------------"

    $sheetData = Read-SheetData -SheetId $profile.SpreadsheetId -TargetRange "A:Y"
    if (-not $sheetData -or -not $sheetData.Rows -or $sheetData.Rows.Count -eq 0) {
        Write-Warning "No rows found in $g spreadsheet."
        continue
    }

    $header = $sheetData.Header
    $rows = $sheetData.Rows
    $modifiedSheet = $false
    $updatedRows = @()

    # Pre-load known personal blogs
    $personalMap = Get-KnownPersonalBlogDomainMap

    $rowIndex = 1
    foreach ($row in $rows) {
        $rowIndex++
        if ($availableCalls -le 0) {
            $updatedRows += ,$row
            continue
        }

        $siteName = if ($row.Count -gt 3) { [string]$row[3] } else { "" }
        $siteUrl  = if ($row.Count -gt 4) { [string]$row[4] } else { "" }
        if ([string]::IsNullOrWhiteSpace($siteName) -and [string]::IsNullOrWhiteSpace($siteUrl)) {
            $updatedRows += ,$row
            continue
        }

        # Extract winning keywords from columns 6 to 21
        $currentKws = @()
        for ($colIdx = 6; $colIdx -le 21; $colIdx++) {
            if ($row.Count -gt $colIdx -and -not [string]::IsNullOrWhiteSpace($row[$colIdx])) {
                $rawKw = ([string]$row[$colIdx]).Trim()
                if ($rawKw.StartsWith($starChar) -or $rawKw.StartsWith($starFull)) {
                    $currentKws += @{
                        ColIndex = $colIdx
                        RawText  = $rawKw
                    }
                }
            }
        }

        if ($currentKws.Count -eq 0) {
            $updatedRows += ,$row
            continue
        }

        $rowModified = $false
        $remainingKws = @()
        $maxStarsInRow = 0
        $serpApiVerifiedCount = 0
        $verifiedKwDetails = @()

        foreach ($kwEntry in $currentKws) {
            if ($availableCalls -le 0) {
                $remainingKws += $kwEntry.RawText
                continue
            }

            $rawKwText = $kwEntry.RawText
            $cleanKw = $rawKwText -replace "^\s*[\u2605\u2606]+", ""
            $volStr = ""
            if ($cleanKw -match $parenPattern) {
                $volStr = $matches[0]
                $cleanKw = ($cleanKw -replace $parenPattern, "").Trim()
            } else {
                $cleanKw = $cleanKw.Trim()
            }

            # Duplicate Verification Prevention Guard (Check row status, remark and keyword SQLite history)
            $existingStatus = if ($row.Count -gt 0) { [string]$row[0] } else { "" }
            $existingRemark = if ($row.Count -gt 24) { [string]$row[24] } else { "" }
            $rowSerpDate = ""
            if ($existingStatus -match "\b(\d{4}-\d{2}-\d{2})\)") {
                $rowSerpDate = $matches[1]
            } elseif ($existingRemark -match "\[SerpApi[^:\]]*:\s*(\d{4}-\d{2}-\d{2})") {
                $rowSerpDate = $matches[1]
            } elseif ($existingRemark -match "\((\d{4}-\d{2}-\d{2})\)") {
                $rowSerpDate = $matches[1]
            }

            $kwHist = Get-SerpApiKeywordLastVerifiedDate -Keyword $cleanKw
            $isRecentlyVerified = $false
            $recentReason = ""
            $todayDate = (Get-Date).ToString("yyyy-MM-dd")

            if (-not $Force) {
                # 1. Strict same-day duplicate check (Already verified today)
                if ($rowSerpDate -eq $todayDate -or $kwHist.LastVerifiedDate -eq $todayDate) {
                    $isRecentlyVerified = $true
                    $recentReason = "Already verified today ($todayDate)"
                }
                # 2. Minimum interval check (MinDays)
                elseif ($kwHist.IsVerified -and $kwHist.DaysAgo -lt $MinDays) {
                    $isRecentlyVerified = $true
                    $recentReason = "Verified $($kwHist.DaysAgo) days ago ($($kwHist.LastVerifiedDate)), min interval is $MinDays days"
                }
            }

            if ($isRecentlyVerified -and -not $SyncCached) {
                Write-Output "`n  [SKIP DUPLICATE] Row $rowIndex '$cleanKw': $recentReason. Skipping API call."
                $totalSkipped++
                $remainingKws += $rawKwText
                $serpApiVerifiedCount++
                $verifiedKwDetails += "$cleanKw"
                continue
            }

            Write-Output "`n  [Verifying Row $rowIndex] '$cleanKw' (Current: $rawKwText)..."

            # Execute SerpApi Search (or Mock)
            $serpResult = $null
            if ($MockMode) {
                # In Mock mode, trigger star loss on even row index to demonstrate deletion
                $isStarLossScenario = ($rowIndex % 2 -eq 0)
                if ($isStarLossScenario) {
                    Write-Output "    [Mock] Simulating STAR LOSS scenario (Top 10 filled by corporate giants)..."
                    $serpResult = [PSCustomObject]@{
                        Keyword         = $cleanKw
                        IsExhausted     = $false
                        ExhaustionError = ""
                        OrganicResults  = @(
                            [PSCustomObject]@{ position = 1; link = "https://www.amazon.co.jp/dp/sample"; title = "Amazon" },
                            [PSCustomObject]@{ position = 2; link = "https://kakaku.com/sample"; title = "Kakaku" },
                            [PSCustomObject]@{ position = 3; link = "https://www.rakuten.co.jp/sample"; title = "Rakuten" }
                        )
                    }
                } else {
                    Write-Output "    [Mock] Simulating ACTIVE STAR scenario (Chiebukuro + Personal Blog in Top 10)..."
                    $serpResult = [PSCustomObject]@{
                        Keyword         = $cleanKw
                        IsExhausted     = $false
                        ExhaustionError = ""
                        OrganicResults  = @(
                            [PSCustomObject]@{ position = 1; link = "https://detail.chiebukuro.yahoo.co.jp/qa/question_detail/q1"; title = "Yahoo" },
                            [PSCustomObject]@{ position = 2; link = "https://note.com/user/n/sample"; title = "note" },
                            [PSCustomObject]@{ position = 3; link = "https://sample-personal-blog.com/review"; title = "Blog" }
                        )
                    }
                    $personalMap["sample-personal-blog.com"] = 2
                }
            } elseif ($SyncCached) {
                # Zero-cost sync: use the latest STORED Google SERP; never call the remote API.
                $serpResult = Get-SerpApiStoredResult -Keyword $cleanKw
                if (-not $serpResult.Found) {
                    Write-Output "    [NO STORED EVIDENCE] '$cleanKw' has no stored Google SERP. Left unchanged (needs a real SerpApi check)."
                    $totalSkipped++
                    $remainingKws += $rawKwText
                    continue
                }
                Write-Output "    [Stored Google SERP] Using evidence fetched at $($serpResult.FetchedAt)."
            } else {
                try {
                    $serpResult = Invoke-SerpApiSearch -Keyword $cleanKw -ApiKey $ApiKey -DryRun:$DryRun
                } catch {
                    Write-Warning "SerpApi search failed for '$cleanKw': $_"
                    $remainingKws += $rawKwText
                    continue
                }
            }

            if ($serpResult.IsExhausted) {
                Write-Warning "SerpApi quota exhausted: $($serpResult.ExhaustionError). Stopping further calls."
                $availableCalls = 0
                $remainingKws += $rawKwText
                continue
            }

            if ($DryRun) {
                Write-Output "    [DryRun] Checked '$cleanKw' successfully (Simulated)."
                $remainingKws += $rawKwText
                $availableCalls--
                $totalVerified++
                continue
            }

            $availableCalls--
            $totalVerified++
            $serpApiVerifiedCount++

            # Evaluate SERP entries
            $eval = Evaluate-SerpApiResults -Keyword $cleanKw -OrganicResults $serpResult.OrganicResults -Gender $g -KnownPersonalBlogMap $personalMap

            Write-Output "    -> SerpApi Evaluation: Total Qualifying Seats: $($eval.TotalSeats) (UGC: $($eval.WeakUgcSeats), Blogs: $($eval.PersonalBlogSeats))"

            # Persist the confirmed star count (previously always stored as 0) for 3-way reconciliation evidence
            try {
                $safeKwLog = $cleanKw.Replace("'", "''")
                $updSql = "UPDATE serpapi_call_logs SET star_count = $([int]$eval.TotalSeats) WHERE id = (SELECT id FROM serpapi_call_logs WHERE keyword = '$safeKwLog' ORDER BY id DESC LIMIT 1);"
                Invoke-SqliteNonQuery -SqlScript $updSql -DbPath (Initialize-SerpApiDatabase) | Out-Null
            } catch {
                Write-Warning "Failed to persist star_count for '$cleanKw': $_"
            }

            # Check if star count is 0 (STAR LOST -> DELETE KEYWORD)
            if ($eval.IsStarLost) {
                Write-Output "    >>> [KW DELETED] '$cleanKw' lost all qualifying seats in Top 10 Google results (Stars: 0). REMOVING FROM SHEET."
                $totalDeleted++
                $rowModified = $true
                # Note: Not adding to $remainingKws -> keyword is deleted!
            } else {
                # Updated keyword with new star count
                $newFormattedKw = "$($eval.StarString)$cleanKw$volStr"
                if ($newFormattedKw -ne $rawKwText) {
                    Write-Output "    >>> [STAR UPDATED] '$rawKwText' -> '$newFormattedKw' (Seats: $($eval.TotalSeats))"
                    $totalUpdated++
                    $rowModified = $true
                } else {
                    Write-Output "    -> [UNCHANGED] Star count matches current sheet ($($eval.StarString))."
                    $totalUnchanged++
                }
                $remainingKws += $newFormattedKw
                $verifiedKwDetails += "$cleanKw($($eval.StarString)$($eval.StarCount))"
                if ($eval.StarCount -gt $maxStarsInRow) {
                    $maxStarsInRow = $eval.StarCount
                }
            }
        }

        # Reconstruct row data if modified or verified
        if ($rowModified -or $serpApiVerifiedCount -gt 0) {
            $modifiedSheet = $true
            $newRow = New-Object System.Collections.ArrayList
            for ($c = 0; $c -le 5; $c++) {
                $val = if ($row.Count -gt $c) { $row[$c] } else { "" }
                [void]$newRow.Add($val)
            }

            # If all keywords were deleted due to star loss, purge the site completely from spreadsheet
            if ($remainingKws.Count -eq 0) {
                Write-Output "  >>> [SITE PURGED] Site '$siteName' has 0 remaining winning keywords. Removing site row from spreadsheet."
                $modifiedSheet = $true
                continue
            }

            # Update Col A (Status) based on multi-keyword progress (Option 1 Standard):
            # - All verified: 🟢 SERP全件済 (N/N件 YYYY-MM-DD)
            # - Partial verified: 🟡 SERP一部済 (M/N件 YYYY-MM-DD)
            $todayDate = (Get-Date).ToString("yyyy-MM-dd")
            $remCount = $remainingKws.Count
            if ($serpApiVerifiedCount -ge $remCount) {
                $strAll = [System.Text.Encoding]::UTF8.GetString(@(0xF0,0x9F,0x9F,0xA2,0x20,0x53,0x45,0x52,0x50,0xE5,0x85,0xA8,0xE4,0xBB,0xB6,0xE6,0xB8,0x88,0x20,0x28)) # "🟢 SERP全件済 ("
                $strUnit = [System.Text.Encoding]::UTF8.GetString(@(0xE4,0xBB,0xB6,0x20)) # "件 "
                $newRow[0] = "$strAll$remCount/$remCount$strUnit$todayDate)"
            } elseif ($serpApiVerifiedCount -gt 0) {
                $strPart = [System.Text.Encoding]::UTF8.GetString(@(0xF0,0x9F,0x9F,0xA1,0x20,0x53,0x45,0x52,0x50,0xE4,0xB8,0x80,0xE9,0x83,0xA8,0xE6,0xB8,0x88,0x20,0x28)) # "🟡 SERP一部済 ("
                $strUnit = [System.Text.Encoding]::UTF8.GetString(@(0xE4,0xBB,0xB6,0x20)) # "件 "
                $newRow[0] = "$strPart$serpApiVerifiedCount/$remCount$strUnit$todayDate)"
            }

            # Fill columns 6 to 21 with remaining keywords
            for ($kIdx = 0; $kIdx -lt 16; $kIdx++) {
                if ($kIdx -lt $remainingKws.Count) {
                    [void]$newRow.Add($remainingKws[$kIdx])
                } else {
                    [void]$newRow.Add("")
                }
            }

            # Col 22: Star rating (Col W)
            $newStarText = if ($maxStarsInRow -gt 0) {
                [string]::new($starChar, $maxStarsInRow) + " ($maxStarsInRow)"
            } else {
                if ($remainingKws.Count -gt 0 -and $row.Count -gt 22) { $row[22] } else { "$starChar (0)" }
            }
            [void]$newRow.Add($newStarText)

            # Col 23: Last verified date (Col X)
            $newRow.Add($todayDate)

            # Col 24: Remarks with SerpApi evidence (Col Y)
            $existingRemark = if ($row.Count -gt 24) { [string]$row[24] } else { "" }
            $leftB = [char]0x3010
            $rightB = [char]0x3011
            $cleanedRem = $existingRemark -replace '\[SerpApi[^\]]+\]', ''
            $cleanedRem = $cleanedRem -replace ($leftB + '[^' + $rightB + ']*' + $rightB), ''
            $strTagPrefix = [System.Text.Encoding]::UTF8.GetString(@(0xE3,0x80,0x90,0x53,0x45,0x52,0x50,0xE6,0xB8,0x88,0x3A,0x20)) # "【SERP済: "
            $kwDetailStr = ($verifiedKwDetails | Select-Object -Unique) -join ', '
            $serpTag = "$strTagPrefix$kwDetailStr ($todayDate)$rightB"
            $newRemark = ("$serpTag " + $cleanedRem.Trim()).Trim()
            [void]$newRow.Add($newRemark)

            $updatedRows += ,$newRow.ToArray()
        } else {
            $updatedRows += ,$row
        }
    }

    # Commit updated rows back to spreadsheet if changes occurred and not DryRun
    if ($modifiedSheet -and -not $DryRun) {
        Write-Output "`n>>> Committing updated rows to $($profile.SheetTitle) ($($updatedRows.Count) rows)..."
        try {
            $fullPayloadRows = New-Object System.Collections.ArrayList
            [void]$fullPayloadRows.Add($header)
            foreach ($ur in $updatedRows) {
                [void]$fullPayloadRows.Add($ur)
            }
            $res = Update-SheetAtomic -Rows $fullPayloadRows.ToArray() -SheetId $profile.SpreadsheetId -TargetSheetName $profile.SheetTitle -AllowHealing:$true
            Write-Output ">>> [SUCCESS] Spreadsheet updated successfully (Updated cells: $($res.UpdatedCells))."
        } catch {
            Write-Warning "Failed to commit updates to spreadsheet: $_"
        }
    }
}

Write-Output "`n=========================================================="
Write-Output "=== SERPAPI VERIFICATION RUN COMPLETED ==="
Write-Output "=========================================================="
Write-Output "Keywords Verified : $totalVerified"
Write-Output "Keywords Updated  : $totalUpdated"
Write-Output "Keywords Deleted  : $totalDeleted (0 stars / lost qualifying seats)"
Write-Output "Keywords Skipped  : $totalSkipped (Duplicate prevention / recently verified)"
Write-Output "Keywords Unchanged: $totalUnchanged"
$finalUsage = Get-SerpApiDailyUsage -DailyLimit 7 -MonthlyLimit 240
Write-Output "Daily Quota Usage : $($finalUsage.CallsToday) / $($finalUsage.DailyLimit) calls today (Month: $($finalUsage.CallsThisMonth) / $($finalUsage.MonthlyLimit), Remaining: $($finalUsage.RemainingCalls))"
Write-Output "=========================================================="
