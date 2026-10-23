<#
.SYNOPSIS
    tools/sheet_inspect.ps1
    Responsibility: Inspect spreadsheet rows (male, female, or both) with a clean 1-line-per-site summary.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("both", "female", "male")]
    [string]$Gender = "both",

    [Parameter(Mandatory=$false)]
    [int]$StartRow = 2,

    [Parameter(Mandatory=$false)]
    [int]$EndRow = 50
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"

$gendersToInspect = if ($Gender -eq "both") { @("female", "male") } else { @($Gender) }

foreach ($g in $gendersToInspect) {
    $profile = Resolve-SheetProfile -Gender $g
    $data = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName
    $rows = $data.Rows
    $header = $data.Header

    Write-Output "`n=========================================================="
    Write-Output "=== $($g.ToUpper()) SPREADSHEET ROWS ($($profile.SheetTitle)) ==="
    Write-Output "=========================================================="

    $kwStartCol = $profile.KwStartCol
    $results = @()

    for ($i = 0; $i -lt $rows.Count; $i++) {
        $rowNum = $i + 2
        if ($rowNum -lt $StartRow -or $rowNum -gt $EndRow) { continue }

        $r = $rows[$i]
        $status = if ($r.Count -gt 0) { [string]$r[0] } else { "" }
        $genreId = if ($r.Count -gt 1) { [string]$r[1] } else { "" }
        $siteName = if ($r.Count -gt 3) { [string]$r[3] } else { "" }
        $url = if ($r.Count -gt 4) { [string]$r[4] } else { "" }
        $da = if ($r.Count -gt 5) { [string]$r[5] } else { "" }
        $starsCol = if ($r.Count -gt 22) { [string]$r[22] } else { "" }
        $date = if ($r.Count -gt 23) { [string]$r[23] } else { "" }

        $kws = @()
        for ($c = $kwStartCol; $c -lt [Math]::Min($r.Count, ($kwStartCol + 16)); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $lines = $val -split "`r?`n"
                foreach ($l in $lines) {
                    $t = $l.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($t)) {
                        $kws += $t
                    }
                }
            }
        }

        $results += [PSCustomObject]@{
            Row = $rowNum
            Status = $status
            Genre = $genreId
            Site = $siteName
            DA = $da
            KwCount = $kws.Count
            Stars = $starsCol
            Date = $date
            Keywords = ($kws -join " | ")
        }
    }

    if ($results.Count -eq 0) {
        Write-Output "No rows found in range $StartRow..$EndRow."
    } else {
        $results | Format-Table -Property Row, Genre, Site, DA, KwCount, Stars, Date -AutoSize
    }
}
