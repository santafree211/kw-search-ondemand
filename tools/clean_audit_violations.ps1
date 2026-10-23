<#
.SYNOPSIS
    tools/clean_audit_violations.ps1
    One-time cleanup script using pure ASCII and unicode codepoints.
#>

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\sheet_atomic_writer.ps1"

Write-Output "=== Starting Targeted Audit Violations Cleanup ==="

$starChar = [char]0x2606 # empty star
$starBlack = [char]0x2605
$starEmoji = [char]0x2B50 # yellow star

# -------------------------------------------------------------
# 1. FEMALE SHEET CLEANUP
# -------------------------------------------------------------
$femProfile = Resolve-SheetProfile -Gender female
$femData = Read-SheetData -SheetId $femProfile.SpreadsheetId -TargetSheetName $femProfile.TargetSheetName
$femHeader = $femData.Header
$femRows = $femData.Rows

Write-Output "Female Sheet - Loaded $($femRows.Count) rows."

$kwJikoCheck = [System.Text.Encoding]::UTF8.GetString(@(0xE8,0x87,0xAA,0xE5,0xB7,0xB1,0xE8,0x82,0xAF,0xE5,0xAE,0x9A,0xE6,0x84,0x9F,0x20,0xE4,0xBD,0x8E,0xE3,0x81,0x84)) # 自己肯定感 低い
$kwSilkWash = [System.Text.Encoding]::UTF8.GetString(@(0xE3,0x82,0xB7,0xE3,0x83,0xAB,0xE3,0x82,0xAF,0x20,0xE6,0xB4,0x97,0xE6,0xBF,0xAF)) # シルク 洗濯
$kwZekkenDaiso = [System.Text.Encoding]::UTF8.GetString(@(0xE3,0x82,0xBC,0xE3,0x83,0x83,0xE3,0x82,0xB1,0xE3,0x83,0xB3,0x20,0xE3,0x82,0x20,0xE3,0x83,0x80,0xE3,0x82,0xA4,0xE3,0x82,0xBD,0xE3,0x83,0xBC)) # ゼッケン ダイソー
$kwOfuroKagami = [System.Text.Encoding]::UTF8.GetString(@(0xE3,0x81,0x8A,0xE9,0xA2,0xA8,0xE5,0x91,0x82,0x20,0xE9,0x8F,0xA1)) # お風呂 鏡
$kwNightBra = [System.Text.Encoding]::UTF8.GetString(@(0xE3,0x83,0x8A,0xE3,0x82,0xA4,0xE3,0x83,0x88,0xE3,0x83,0x96,0xE3,0x83,0x9 those,0x83,0xA9)) # ナイトブラ

$newFemRows = @()
for ($i = 0; $i -lt $femRows.Count; $i++) {
    $rowNum = $i + 2
    $r = [System.Collections.ArrayList]::new([object[]]$femRows[$i])

    # Row 26: Drop row (履歴書 セリア - 0 seats on Google)
    if ($rowNum -eq 26) {
        Write-Output "Female: Dropping Row 26"
        continue
    }

    # Row 6: 自己肯定感 低い -> change to 1 star
    if ($rowNum -eq 6) {
        for ($c = 6; $c -lt $r.Count; $c++) {
            $val = [string]$r[$c]
            if ($val.Contains("自己肯定感") -and $val.Contains("低い")) {
                $r[$c] = ($val -replace "^[^\(]*", "$starChar ")
            }
        }
    }

    # Row 29: シルク 洗濯 -> change to 2 stars
    if ($rowNum -eq 29) {
        for ($c = 6; $c -lt $r.Count; $c++) {
            $val = [string]$r[$c]
            if ($val.Contains("シルク") -and $val.Contains("洗濯")) {
                $r[$c] = ($val -replace "^[^\(]*", "$starChar$starChar ")
            }
        }
    }

    # Row 30: ゼッケン ダイソー -> change to 3 stars
    if ($rowNum -eq 30) {
        for ($c = 6; $c -lt $r.Count; $c++) {
            $val = [string]$r[$c]
            if ($val.Contains("ゼッケン") -and $val.Contains("ダイソー")) {
                $r[$c] = ($val -replace "^[^\(]*", "$starChar$starChar$starChar ")
            }
        }
    }

    # Row 34: remove duplicate 'お風呂 鏡'
    if ($rowNum -eq 34) {
        $cleanCells = @()
        for ($c = 0; $c -lt 6; $c++) { $cleanCells += $r[$c] }
        for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not ($val.Contains("お風呂") -and $val.Contains("鏡"))) {
                $cleanCells += $val
            }
        }
        $r = [System.Collections.ArrayList]::new([object[]]$cleanCells)
    }

    # Row 36: remove duplicate 'ナイトブラ効果'
    if ($rowNum -eq 36) {
        $cleanCells = @()
        for ($c = 0; $c -lt 6; $c++) { $cleanCells += $r[$c] }
        for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not $val.Contains("ナイトブラ")) {
                $cleanCells += $val
            }
        }
        $r = [System.Collections.ArrayList]::new([object[]]$cleanCells)
    }

    # Row 37: remove duplicate 'シルク 洗濯'
    if ($rowNum -eq 37) {
        $cleanCells = @()
        for ($c = 0; $c -lt 6; $c++) { $cleanCells += $r[$c] }
        for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not ($val.Contains("シルク") -and $val.Contains("洗濯"))) {
                $cleanCells += $val
            }
        }
        $r = [System.Collections.ArrayList]::new([object[]]$cleanCells)
    }

    $newFemRows += ,@($r)
}

# Rebuild Female payload with updated Col 22 summary
$fullFemPayload = @(, @($femHeader))
foreach ($row in $newFemRows) {
    $stars = @()
    for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
        $val = [string]$row[$c]
        if ($val -match "^([☆★\u2B50]+)") {
            $stars += $matches[1].Length
        }
    }
    if ($stars.Count -gt 0) {
        $minS = ($stars | Measure-Object -Minimum).Minimum
        $maxS = ($stars | Measure-Object -Maximum).Maximum
        $tilde = [char]0x301C
        $summary = if ($minS -eq $maxS) { ("$starEmoji" * $minS) + " ($minS)" } else { ("$starEmoji" * $minS) + $tilde + ("$starEmoji" * $maxS) }
        while ($row.Count -le 22) { $row += "" }
        $row[22] = $summary
    }
    $fullFemPayload += ,@($row)
}

Write-Output "Writing cleaned Female rows to spreadsheet..."
Update-SheetAtomic -Rows $fullFemPayload -SheetId $femProfile.SpreadsheetId -TargetSheetName $femProfile.TargetSheetName -AllowHealing -ClearTarget "A2:Y100"


# -------------------------------------------------------------
# 2. MALE SHEET CLEANUP
# -------------------------------------------------------------
$maleProfile = Resolve-SheetProfile -Gender male
$maleData = Read-SheetData -SheetId $maleProfile.SpreadsheetId -TargetSheetName $maleProfile.TargetSheetName
$maleHeader = $maleData.Header
$maleRows = $maleData.Rows

Write-Output "Male Sheet - Loaded $($maleRows.Count) rows."

$newMaleRows = @()
for ($i = 0; $i -lt $maleRows.Count; $i++) {
    $rowNum = $i + 2
    $r = [System.Collections.ArrayList]::new([object[]]$maleRows[$i])

    # Row 20: 履歴書 セリア -> Drop row
    if ($rowNum -eq 20) {
        Write-Output "Male: Dropping Row 20"
        continue
    }

    # Row 42: GOLF SHOP WILL -> Drop row
    if ($rowNum -eq 42) {
        Write-Output "Male: Dropping Row 42"
        continue
    }

    # Row 14: remove duplicate '光熱費平均一人暮らし'
    if ($rowNum -eq 14) {
        $cleanCells = @()
        for ($c = 0; $c -lt 6; $c++) { $cleanCells += $r[$c] }
        for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not $val.Contains("光熱費")) {
                $cleanCells += $val
            }
        }
        $r = [System.Collections.ArrayList]::new([object[]]$cleanCells)
    }

    # Row 26: remove duplicate '家系ラーメン クックら'
    if ($rowNum -eq 26) {
        $cleanCells = @()
        for ($c = 0; $c -lt 6; $c++) { $cleanCells += $r[$c] }
        for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not $val.Contains("クックら")) {
                $cleanCells += $val
            }
        }
        $r = [System.Collections.ArrayList]::new([object[]]$cleanCells)
    }

    # Row 37: remove duplicate 'ステーキ リベラ'
    if ($rowNum -eq 37) {
        $cleanCells = @()
        for ($c = 0; $c -lt 6; $c++) { $cleanCells += $r[$c] }
        for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not $val.Contains("リベラ")) {
                $cleanCells += $val
            }
        }
        $r = [System.Collections.ArrayList]::new([object[]]$cleanCells)
    }

    # Row 41: remove duplicate '祖母山北谷登山口'
    if ($rowNum -eq 41) {
        $cleanCells = @()
        for ($c = 0; $c -lt 6; $c++) { $cleanCells += $r[$c] }
        for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not $val.Contains("祖母山")) {
                $cleanCells += $val
            }
        }
        $r = [System.Collections.ArrayList]::new([object[]]$cleanCells)
    }

    # Check valid KW count
    $kwCount = 0
    for ($c = 6; $c -lt [Math]::Min($r.Count, 22); $c++) {
        if (-not [string]::IsNullOrWhiteSpace([string]$r[$c])) { $kwCount++ }
    }
    if ($kwCount -eq 0) {
        Write-Output "Male: Row $rowNum has 0 KWs left, dropping row."
        continue
    }

    $newMaleRows += ,@($r)
}

# Count male stars
$mStar3 = 0; $mStar2 = 0; $mStar1 = 0
foreach ($row in $newMaleRows) {
    for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
        $val = [string]$row[$c]
        if ($val -match "^[☆★\u2B50]{3,}") { $mStar3++ }
        elseif ($val -match "^[☆★\u2B50]{2}") { $mStar2++ }
        elseif ($val -match "^[☆★\u2B50]") { $mStar1++ }
    }
}
Write-Output "Male Current Stars: Star3+=$mStar3, Star2=$mStar2, Star1=$mStar1"

# Prune excess Star1 rows if Star1 > Star2 + 1 to satisfy Golden Ratio
if ($mStar1 -gt ($mStar2 + 1)) {
    $excess = $mStar1 - ($mStar2 + 1)
    Write-Output "Pruning $excess excess single Star1 rows..."
    $pruned = 0
    $filteredMaleRows = @()
    for ($i = $newMaleRows.Count - 1; $i -ge 0; $i--) {
        $row = $newMaleRows[$i]
        $rowStar1Kws = @()
        $rowOtherKws = @()
        for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
            $val = [string]$row[$c]
            if ([string]::IsNullOrWhiteSpace($val)) { continue }
            if ($val -match "^[☆★\u2B50]{1}[^☆★\u2B50]") { $rowStar1Kws += $val }
            else { $rowOtherKws += $val }
        }

        if ($pruned -lt $excess -and $rowStar1Kws.Count -gt 0 -and $rowOtherKws.Count -eq 0) {
            Write-Output "Pruning Row: $($row[3])"
            $pruned++
            continue
        }
        $filteredMaleRows = ,$row + $filteredMaleRows
    }
    $newMaleRows = $filteredMaleRows
}

# Rebuild Male payload with updated Col 22 summary
$fullMalePayload = @(, @($maleHeader))
foreach ($row in $newMaleRows) {
    $stars = @()
    for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
        $val = [string]$row[$c]
        if ($val -match "^([☆★\u2B50]+)") {
            $stars += $matches[1].Length
        }
    }
    if ($stars.Count -gt 0) {
        $minS = ($stars | Measure-Object -Minimum).Minimum
        $maxS = ($stars | Measure-Object -Maximum).Maximum
        $tilde = [char]0x301C
        $summary = if ($minS -eq $maxS) { ("$starEmoji" * $minS) + " ($minS)" } else { ("$starEmoji" * $minS) + $tilde + ("$starEmoji" * $maxS) }
        while ($row.Count -le 22) { $row += "" }
        $row[22] = $summary
    }
    $fullMalePayload += ,@($row)
}

Write-Output "Writing cleaned Male rows to spreadsheet..."
Update-SheetAtomic -Rows $fullMalePayload -SheetId $maleProfile.SpreadsheetId -TargetSheetName $maleProfile.TargetSheetName -AllowHealing -ClearTarget "A2:Y100"

Write-Output "=== Cleanup Execution Finished Successfully ==="
