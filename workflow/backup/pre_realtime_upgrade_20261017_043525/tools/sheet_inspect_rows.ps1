<#
.SYNOPSIS
    tools/sheet_inspect_rows.ps1
    Responsibility: Inspect spreadsheet rows cleanly with 1-line-per-site summary for token efficiency.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [int]$StartRow = 2,

    [Parameter(Mandatory=$false)]
    [int]$EndRow = 50,

    [Parameter(Mandatory=$false)]
    [string]$SpreadsheetId = "",

    [Parameter(Mandatory=$false)]
    [string]$Gender = "",

    [Parameter(Mandatory=$false)]
    [string]$SheetName = ""
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\sheet_profile_resolver.ps1"
. "$PSScriptRoot\..\workflow\scripts\sheet_data_reader.ps1"

$profile = Resolve-SheetProfile -SpreadsheetId $SpreadsheetId -Gender $Gender
$SpreadsheetId = $profile.SpreadsheetId

$data = Read-SheetData -SheetId $SpreadsheetId -TargetSheetName $SheetName
$rows = $data.Rows
$header = $data.Header

$results = @()
$kwStartCol = 6
for ($i = 0; $i -lt $header.Count; $i++) {
    $h = [string]$header[$i]
    if ($h.Contains("KW1")) {
        $kwStartCol = $i
        break
    }
}

for ($i = 0; $i -lt $rows.Count; $i++) {
    $rowNum = $i + 2
    if ($rowNum -lt $StartRow -or $rowNum -gt $EndRow) { continue }

    $r = $rows[$i]
    $dateOrStatus = if ($r.Count -gt 0) { [string]$r[0] } else { "" }
    $siteName = if ($r.Count -gt 1) { [string]$r[1] } else { "" }
    $da = if ($r.Count -gt 4) { [string]$r[4] } else { "" }
    $kws = @()
    $maxCol = [Math]::Min($r.Count, ($header.Count - 1))
    for ($c = $kwStartCol; $c -lt $maxCol; $c++) {
        $val = [string]$r[$c]
        if (-not [string]::IsNullOrWhiteSpace($val)) {
            $kws += $val.Trim()
        }
    }

    $results += [PSCustomObject]@{
        Row = $rowNum
        Date = $dateOrStatus
        Site = $siteName
        DA = $da
        KwCount = $kws.Count
        Keywords = ($kws -join " | ")
    }
}

$results | Format-Table -AutoSize
