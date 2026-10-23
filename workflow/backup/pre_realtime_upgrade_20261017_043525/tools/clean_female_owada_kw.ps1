$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_data_reader.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_atomic_writer.ps1"

$p = Resolve-SheetProfile -Gender female
$data = Read-SheetData -SheetId $p.SpreadsheetId -TargetSheetName $p.TargetSheetName

$cleanRows = [System.Collections.Generic.List[object]]::new()
$cleanRows.Add($data.RawValues[0]) # Header

$modified = $false
for ($i = 1; $i -lt $data.RawValues.Count; $i++) {
    $row = $data.RawValues[$i]
    $rowStr = $row -join " "
    if ($rowStr -match "小和田哲男 雅子さま 親戚") {
        Write-Host "Found row with target KW at Row $($i+1): Removing KW"
        $newRow = [System.Collections.Generic.List[object]]::new()
        for ($c = 0; $c -le 5; $c++) {
            $newRow.Add(if ($row.Count -gt $c) { $row[$c] } else { "" })
        }
        $kws = [System.Collections.Generic.List[string]]::new()
        for ($c = 6; $c -lt [Math]::Min($row.Count, 22); $c++) {
            $val = [string]$row[$c]
            if (-not [string]::IsNullOrWhiteSpace($val) -and -not ($val -match "小和田哲男 雅子さま 親戚")) {
                $kws.Add($val.Trim())
            }
        }
        foreach ($k in $kws) { $newRow.Add($k) }
        while ($newRow.Count -lt 22) { $newRow.Add("") }
        # summary col
        $stars = [System.Collections.Generic.List[int]]::new()
        foreach ($k in $kws) {
            if ($k.StartsWith("☆☆☆☆☆")) { $stars.Add(5) }
            elseif ($k.StartsWith("☆☆☆☆")) { $stars.Add(4) }
            elseif ($k.StartsWith("☆☆☆")) { $stars.Add(3) }
            elseif ($k.StartsWith("☆☆")) { $stars.Add(2) }
            elseif ($k.StartsWith("☆")) { $stars.Add(1) }
        }
        $starChar = [System.Text.Encoding]::UTF8.GetString(@(0xE2, 0xAD, 0x90))
        $summary = if ($stars.Count -gt 0) {
            $minS = ($stars | Measure-Object -Minimum).Minimum
            $maxS = ($stars | Measure-Object -Maximum).Maximum
            if ($minS -eq $maxS) { "$($starChar * $minS) ($minS)" } else { "$($starChar * $minS)~$($starChar * $maxS)" }
        } else { "" }
        $newRow.Add($summary)
        $newRow.Add(if ($row.Count -gt 23) { $row[23] } else { "" })
        $newRow.Add(if ($row.Count -gt 24) { $row[24] } else { "" })
        $cleanRows.Add($newRow.ToArray())
        $modified = $true
    } else {
        $cleanRows.Add($row)
    }
}

if ($modified) {
    Write-Host "Updating female sheet atomically without invalid KW..."
    $updateRes = Update-SheetAtomic -Rows $cleanRows.ToArray() -SheetId $p.SpreadsheetId -TargetSheetName $p.TargetSheetName -AllowHealing
    Write-Host "Success: Updated cells $($updateRes.UpdatedCells)"
}
