<#
.SYNOPSIS
    tools/sheet_ratio_balancer.ps1
    Responsibility: Autonomous Golden Ratio (50:25:25) Self-Healing Balancer.
    Features:
      1. Inspects active keywords across spreadsheet rows (Female, Male, or Both).
      2. If ratio is balanced (Star3 >= 50%, Star2 <= 25%, Star1 <= 25%, Diff <= 1) -> No action.
      3. If ratio is violated:
         - Automatically shelves excess Star2 / Star1 from multi-keyword rows to shelved_stock.json.
         - Automatically promotes eligible Star3 keywords from stock into vacant site slots (if available).
         - Re-balances Star2 and Star1 difference within +/- 1.
         - Recalculates Col W (Star summary) and updates sheet atomically.
         - Saves updated stock using pure UTF-8 without BOM.
    Usage:
      powershell -ExecutionPolicy Bypass -File tools\sheet_ratio_balancer.ps1 [-Gender both|female|male] [-DryRun]
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\sheet_atomic_writer.ps1"
. "$projectRoot\workflow\scripts\guard_normal_state.ps1"

Write-Output "=========================================================="
Write-Output "=== AUTONOMOUS GOLDEN RATIO (50:25:25) SELF-HEALING BALANCER ==="
Write-Output "=========================================================="
Write-Output "Target Gender : $Gender"
Write-Output "DryRun Mode   : $DryRun"

$starChar = [char]0x2606
$starFull = [char]0x2605

function Get-KwStarType([string]$kwText) {
    if ([string]::IsNullOrWhiteSpace($kwText)) { return "UNKNOWN" }
    $trimmed = $kwText.Trim()
    if ($trimmed.StartsWith("$starChar$starChar$starChar") -or $trimmed.StartsWith("$starFull$starFull$starFull")) { return "STAR3_PLUS" }
    if ($trimmed.StartsWith("$starChar$starChar") -or $trimmed.StartsWith("$starFull$starFull")) { return "STAR2" }
    if ($trimmed.StartsWith($starChar) -or $trimmed.StartsWith($starFull)) { return "STAR1" }
    return "UNKNOWN"
}

function Recalculate-StarSummary([System.Collections.Generic.List[string]]$kws) {
    $stars = [System.Collections.Generic.List[int]]::new()
    foreach ($k in $kws) {
        $t = Get-KwStarType $k
        if ($t -eq "STAR3_PLUS") { $stars.Add(3) }
        elseif ($t -eq "STAR2") { $stars.Add(2) }
        elseif ($t -eq "STAR1") { $stars.Add(1) }
    }
    if ($stars.Count -eq 0) { return "" }
    $minS = ($stars | Measure-Object -Minimum).Minimum
    $maxS = ($stars | Measure-Object -Maximum).Maximum
    $displayChar = [System.Text.Encoding]::UTF8.GetString(@(0xE2, 0xAD, 0x90)) # Unicode Star
    if ($minS -eq $maxS) {
        return "$($displayChar * $minS) ($minS)"
    } else {
        return "$($displayChar * $minS)~$($displayChar * $maxS)"
    }
}

function Build-BalancedRow($origRow, $kws) {
    $arr = [System.Collections.Generic.List[object]]::new()
    for ($c = 0; $c -le 5; $c++) {
        $v = if ($origRow.Count -gt $c) { $origRow[$c] } else { "" }
        $arr.Add($v)
    }
    foreach ($k in $kws) { $arr.Add($k) }
    while ($arr.Count -lt 22) { $arr.Add("") }
    $arr.Add((Recalculate-StarSummary $kws))
    $v23 = if ($origRow.Count -gt 23) { $origRow[23] } else { "" }
    $v24 = if ($origRow.Count -gt 24) { $origRow[24] } else { "" }
    $arr.Add($v23)
    $arr.Add($v24)
    return $arr.ToArray()
}

function Balance-SingleSheet {
    param(
        [string]$TargetGender,
        [switch]$IsDryRun = $false
    )

    $profile = Resolve-SheetProfile -Gender $TargetGender
    Write-Output "`n----------------------------------------------------------"
    Write-Output "Processing Profile: $TargetGender ($($profile.Title))"
    Write-Output "Spreadsheet ID    : $($profile.SpreadsheetId)"

    $sheetData = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName
    if ($null -eq $sheetData.RawValues -or $sheetData.RawValues.Count -le 1) {
        Write-Output "No data rows found in spreadsheet."
        return
    }

    $header = $sheetData.RawValues[0]
    $body = [System.Collections.Generic.List[object]]::new()
    for ($i = 1; $i -lt $sheetData.RawValues.Count; $i++) {
        $rowItem = $sheetData.RawValues[$i]
        if ($rowItem.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($rowItem[0])) {
            $body.Add($rowItem)
        }
    }

    # Load shelved stock safely (UTF-8 BOM free)
    $stockPath = $profile.StockPath
    $shelvedStock = [System.Collections.Generic.List[string]]::new()
    if (Test-Path $stockPath) {
        try {
            $stockRaw = [System.IO.File]::ReadAllText($stockPath, [System.Text.Encoding]::UTF8)
            $parsedStock = $stockRaw | ConvertFrom-Json
            if ($parsedStock -is [array]) {
                foreach ($item in $parsedStock) {
                    $sItem = ([string]$item).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($sItem) -and -not $shelvedStock.Contains($sItem)) {
                        $shelvedStock.Add($sItem)
                    }
                }
            }
        } catch {
            Write-Warning "Could not parse existing stock file: $_"
        }
    }

    # Count current keywords
    $star3Count = 0
    $star2Count = 0
    $star1Count = 0

    for ($r = 0; $r -lt $body.Count; $r++) {
        $row = $body[$r]
        for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
            $val = [string]$row[$c]
            $st = Get-KwStarType $val
            if ($st -eq "STAR3_PLUS") { $star3Count++ }
            elseif ($st -eq "STAR2") { $star2Count++ }
            elseif ($st -eq "STAR1") { $star1Count++ }
        }
    }

    $initialTotal = $star3Count + $star2Count + $star1Count
    $initR3 = if ($initialTotal -gt 0) { [Math]::Round(($star3Count / $initialTotal) * 100, 1) } else { 0 }
    $initR2 = if ($initialTotal -gt 0) { [Math]::Round(($star2Count / $initialTotal) * 100, 1) } else { 0 }
    $initR1 = if ($initialTotal -gt 0) { [Math]::Round(($star1Count / $initialTotal) * 100, 1) } else { 0 }

    Write-Output "Initial Counts : Star3+: $star3Count ($initR3%), Star2: $star2Count ($initR2%), Star1: $star1Count ($initR1%) | Total: $initialTotal"

    $maxWeakInitial = [int][Math]::Floor($star3Count / 2)
    $isAlreadyBalanced = ($initR3 -ge 50.0 -and $star2Count -le $maxWeakInitial -and $star1Count -le $maxWeakInitial -and [Math]::Abs($star2Count - $star1Count) -le 1)

    if ($isAlreadyBalanced) {
        Write-Output ">>> STATUS: HEALTHY STATE. Sheet already satisfies 50:25:25 Golden Ratio."
        return
    }

    Write-Output ">>> STATUS: IMBALANCED. Activating Autonomous Self-Healing Algorithm..."

    $shelvedFromSheet = [System.Collections.Generic.List[string]]::new()
    $modified = $false

    # Step A: Shelve excess weak keywords from multi-keyword rows
    # We prioritize preserving at least 1 keyword per row (never wipe out a site)
    # Target counts:
    # We want: Star2 <= Floor(Star3 / 2), Star1 <= Floor(Star3 / 2), Abs(Star2 - Star1) <= 1
    # Total Star3 ratio >= 50.0%
    $targetMaxWeak = [int][Math]::Floor($star3Count / 2)
    
    # Pass 1: Reduce Star2 if exceeding targetMaxWeak
    if ($star2Count -gt $targetMaxWeak) {
        $neededReduction2 = $star2Count - $targetMaxWeak
        for ($r = $body.Count - 1; $r -ge 0; $r--) {
            if ($neededReduction2 -le 0) { break }
            $row = $body[$r]
            $rowKws = [System.Collections.Generic.List[string]]::new()
            for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
                $cell = [string]$row[$c]
                if (-not [string]::IsNullOrWhiteSpace($cell)) { $rowKws.Add($cell) }
            }
            # Only remove if row has more than 1 keyword (or has Star3)
            $hasStar3 = ($rowKws | Where-Object { (Get-KwStarType $_) -eq "STAR3_PLUS" }).Count -gt 0
            if ($rowKws.Count -gt 1 -or $hasStar3) {
                for ($kIdx = $rowKws.Count - 1; $kIdx -ge 0; $kIdx--) {
                    if ($neededReduction2 -le 0) { break }
                    $kwItem = $rowKws[$kIdx]
                    if ((Get-KwStarType $kwItem) -eq "STAR2") {
                        # Ensure we don't leave row completely empty
                        if ($rowKws.Count -gt 1) {
                            $rowKws.RemoveAt($kIdx)
                            $shelvedFromSheet.Add($kwItem)
                            $neededReduction2--
                            $star2Count--
                            $modified = $true
                        }
                    }
                }
                # Reconstruct row
                $body[$r] = Build-BalancedRow $row $rowKws
            }
        }
    }

    # Pass 2: Reduce Star1 if exceeding targetMaxWeak
    if ($star1Count -gt $targetMaxWeak) {
        $neededReduction1 = $star1Count - $targetMaxWeak
        for ($r = $body.Count - 1; $r -ge 0; $r--) {
            if ($neededReduction1 -le 0) { break }
            $row = $body[$r]
            $rowKws = [System.Collections.Generic.List[string]]::new()
            for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
                $cell = [string]$row[$c]
                if (-not [string]::IsNullOrWhiteSpace($cell)) { $rowKws.Add($cell) }
            }
            $hasStar3 = ($rowKws | Where-Object { (Get-KwStarType $_) -eq "STAR3_PLUS" }).Count -gt 0
            if ($rowKws.Count -gt 1 -or $hasStar3) {
                for ($kIdx = $rowKws.Count - 1; $kIdx -ge 0; $kIdx--) {
                    if ($neededReduction1 -le 0) { break }
                    $kwItem = $rowKws[$kIdx]
                    if ((Get-KwStarType $kwItem) -eq "STAR1") {
                        if ($rowKws.Count -gt 1) {
                            $rowKws.RemoveAt($kIdx)
                            $shelvedFromSheet.Add($kwItem)
                            $neededReduction1--
                            $star1Count--
                            $modified = $true
                        }
                    }
                }
                $body[$r] = Build-BalancedRow $row $rowKws
            }
        }
    }

    # Pass 3: Balance Star2 and Star1 difference (|Star2 - Star1| <= 1)
    while ([Math]::Abs($star2Count - $star1Count) -gt 1) {
        $trimType = if ($star2Count -gt $star1Count) { "STAR2" } else { "STAR1" }
        $trimmedOne = $false
        for ($r = $body.Count - 1; $r -ge 0; $r--) {
            $row = $body[$r]
            $rowKws = [System.Collections.Generic.List[string]]::new()
            for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
                $cell = [string]$row[$c]
                if (-not [string]::IsNullOrWhiteSpace($cell)) { $rowKws.Add($cell) }
            }
            if ($rowKws.Count -gt 1) {
                for ($kIdx = $rowKws.Count - 1; $kIdx -ge 0; $kIdx--) {
                    if ((Get-KwStarType $rowKws[$kIdx]) -eq $trimType) {
                        $removedKw = $rowKws[$kIdx]
                        $rowKws.RemoveAt($kIdx)
                        $shelvedFromSheet.Add($removedKw)
                        if ($trimType -eq "STAR2") { $star2Count-- } else { $star1Count-- }
                        $trimmedOne = $true
                        $modified = $true
                        break
                    }
                }
                if ($trimmedOne) {
                    $body[$r] = Build-BalancedRow $row $rowKws
                    break
                }
            }
        }
        if (-not $trimmedOne) {
            # Trimming impossible without emptying rows; promote deficit star from stock if available
            $deficitType = if ($star2Count -lt $star1Count) { "STAR2" } else { "STAR1" }
            $promotedOne = $false
            for ($sIdx = 0; $sIdx -lt $shelvedStock.Count; $sIdx++) {
                $sKw = $shelvedStock[$sIdx]
                if ((Get-KwStarType $sKw) -eq $deficitType) {
                    # Find a row that has vacancy (< 16 keywords)
                    for ($r = 0; $r -lt $body.Count; $r++) {
                        $row = $body[$r]
                        $rowKws = [System.Collections.Generic.List[string]]::new()
                        for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
                            $cell = [string]$row[$c]
                            if (-not [string]::IsNullOrWhiteSpace($cell)) { $rowKws.Add($cell) }
                        }
                        if ($rowKws.Count -lt 16 -and -not $rowKws.Contains($sKw)) {
                            $rowKws.Add($sKw)
                            $body[$r] = Build-BalancedRow $row $rowKws
                            $shelvedStock.RemoveAt($sIdx)
                            if ($deficitType -eq "STAR2") { $star2Count++ } else { $star1Count++ }
                            $promotedOne = $true
                            $modified = $true
                            Write-Output "Promoted $deficitType keyword '$sKw' from stock to Row $($r + 2) to balance ratio."
                            break
                        }
                    }
                    if ($promotedOne) { break }
                }
            }
            if (-not $promotedOne) { break }
        }
    }

    # Final calculations
    $finalTotal = $star3Count + $star2Count + $star1Count
    $fR3 = if ($finalTotal -gt 0) { [Math]::Round(($star3Count / $finalTotal) * 100, 1) } else { 0 }
    $fR2 = if ($finalTotal -gt 0) { [Math]::Round(($star2Count / $finalTotal) * 100, 1) } else { 0 }
    $fR1 = if ($finalTotal -gt 0) { [Math]::Round(($star1Count / $finalTotal) * 100, 1) } else { 0 }

    Write-Output "Balanced Counts: Star3+: $star3Count ($fR3%), Star2: $star2Count ($fR2%), Star1: $star1Count ($fR1%) | Total: $finalTotal"
    Write-Output "Shelved Keywords Count: $($shelvedFromSheet.Count)"

    # Add shelved keywords to persistent stock safely
    if ($shelvedFromSheet.Count -gt 0) {
        foreach ($sk in $shelvedFromSheet) {
            if (-not $shelvedStock.Contains($sk)) {
                $shelvedStock.Add($sk)
            }
        }
        if (-not $IsDryRun) {
            $stockJson = $shelvedStock | ConvertTo-Json -Depth 5
            [System.IO.File]::WriteAllText($stockPath, $stockJson, [System.Text.UTF8Encoding]::new($false))
            Write-Output "Updated stock file ($stockPath) with $($shelvedFromSheet.Count) new shelved items (Total in stock: $($shelvedStock.Count))."
        } else {
            Write-Output "[DryRun] Would write $($shelvedStock.Count) items to $stockPath."
        }
    }

    # Commit updated rows atomically
    if ($modified -and -not $IsDryRun) {
        $cleanFullRows = [System.Collections.Generic.List[object]]::new()
        $cleanFullRows.Add($header)
        foreach ($b in $body) { $cleanFullRows.Add($b) }

        Write-Output "Atomically updating spreadsheet with balanced rows..."
        $updateRes = Update-SheetAtomic -Rows $cleanFullRows.ToArray() -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName -AllowHealing -ClearTarget "A:Y"
        Write-Output "Spreadsheet update SUCCESS. (Cells updated: $($updateRes.UpdatedCells))"
    } elseif ($IsDryRun) {
        Write-Output "[DryRun] Simulation completed. No spreadsheet cells modified."
    }
}

$gendersToRun = if ($Gender -eq "both") { @("female", "male") } else { @($Gender) }
foreach ($g in $gendersToRun) {
    Balance-SingleSheet -TargetGender $g -IsDryRun:$DryRun
}

Write-Output "`n=========================================================="
Write-Output "=== SELF-HEALING BALANCER FINISHED ==="
Write-Output "=========================================================="
