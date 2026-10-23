param()

. "$PSScriptRoot\sheet_profile_resolver.ps1"
. "$PSScriptRoot\sheet_data_reader.ps1"

$twoWeeksAgo = (Get-Date "2026-10-03").AddDays(-14).ToString("yyyy-MM-dd")
Write-Output "Auditing 2-week window (from $twoWeeksAgo to 2026-10-03)..."

$whiteStar = [char]0x2606 # ☆
$blackStar = [char]0x2605 # ★
$starEmoji = [char]0x2B50 # ⭐

foreach ($g in @("female", "male")) {
    $profile = Resolve-SheetProfile -Gender $g
    $data = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName
    $header = $data.Header
    $kwCol = $profile.KwStartCol
    if ($header -is [array]) {
        for ($i = 0; $i -lt $header.Count; $i++) {
            $h = [string]$header[$i]
            if ($h -match "WinningKw1\b" -or $h -match "KW1\b" -or $h.EndsWith("KW1")) {
                $kwCol = $i
                break
            }
        }
    }
    
    $totalKws = 0
    $twoWeeksKws = 0
    $priorKws = 0
    $twoWeeksSites = 0
    $priorSites = 0
    $byDate = @{}
    
    foreach ($r in $data.Rows) {
        $dateStr = if ($r.Count -gt 23) { [string]$r[23] } else { "" }
        if ([string]::IsNullOrWhiteSpace($dateStr)) { $dateStr = "Unknown" }
        $kwsInRow = 0
        for ($c = $kwCol; $c -lt [Math]::Min($r.Count, ($kwCol + 16)); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $lines = $val -split "`r?`n"
                foreach ($l in $lines) {
                    $t = $l.Trim()
                    if ($t.StartsWith($whiteStar) -or $t.StartsWith($blackStar) -or $t.StartsWith($starEmoji)) {
                        $kwsInRow++
                    }
                }
            }
        }
        $totalKws += $kwsInRow
        if (-not $byDate.ContainsKey($dateStr)) {
            $byDate[$dateStr] = @{ Sites = 0; Kws = 0 }
        }
        $byDate[$dateStr].Sites++
        $byDate[$dateStr].Kws += $kwsInRow

        if ($dateStr -ge $twoWeeksAgo -and $dateStr -ne "Unknown") {
            $twoWeeksKws += $kwsInRow
            $twoWeeksSites++
        } else {
            $priorKws += $kwsInRow
            $priorSites++
        }
    }
    
    Write-Output "`n========================================================"
    Write-Output "[$($g.ToUpper()) SHEET: $($profile.Title)]"
    Write-Output "  Total Keywords on Sheet : $totalKws"
    Write-Output "  Keywords Added (2-week) : $twoWeeksKws (Sites: $twoWeeksSites)"
    Write-Output "  Keywords Prior to 2-week: $priorKws (Sites: $priorSites)"
    Write-Output "--- Daily Breakdown ---"
    foreach ($d in ($byDate.Keys | Sort-Object)) {
        Write-Output "  $d : +$($byDate[$d].Kws) KWs ($($byDate[$d].Sites) sites)"
    }
}
