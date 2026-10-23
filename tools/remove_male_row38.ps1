$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_atomic_writer.ps1"

$p = Resolve-SheetProfile -Gender male
$res = Remove-SheetRowAtomic -Predicate {
    param($r, $rowNum)
    $t = $r -join " "
    return ($t -match "履歴書 セリア" -or $t -match "lekky\.jp" -or $t -match "syufu-tiemk")
} -SheetId $p.SpreadsheetId -TargetSheetName $p.TargetSheetName

Write-Host "Row removal result: $($res | ConvertTo-Json -Compress)"
