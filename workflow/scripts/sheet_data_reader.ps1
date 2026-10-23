<#
.SYNOPSIS
    sheet_data_reader.ps1
    Responsibility: Read spreadsheet rows cleanly from Google Sheets API.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\sheet_profile_resolver.ps1"

function Read-SheetData {
    param(
        [string]$SheetId = "",
        [string]$TargetSheetName = "",
        [string]$TargetRange = "A:Y",
        [string]$Token = ""
    )

    if ([string]::IsNullOrWhiteSpace($SheetId)) {
        $profile = Resolve-SheetProfile
        $SheetId = $profile.SpreadsheetId
    }

    if ([string]::IsNullOrWhiteSpace($TargetSheetName)) {
        # Default: 当たりKW (UTF-8 bytes to ensure PowerShell 5.1 compatibility)
        $TargetSheetName = [System.Text.Encoding]::UTF8.GetString(@(0xE5,0xBD,0x93,0xE3,0x81,0x9F,0xE3,0x82,0x8A,0x4B,0x57))
    }

    if ([string]::IsNullOrWhiteSpace($Token)) {
        . "$PSScriptRoot\sheet_auth_provider.ps1"
        $Token = Get-GoogleAccessToken
    }

    $escapedRange = [Uri]::EscapeDataString("'$TargetSheetName'!$TargetRange")
    $url = "https://sheets.googleapis.com/v4/spreadsheets/$SheetId/values/$escapedRange"

    $headers = @{
        Authorization = "Bearer $Token"
    }

    $res = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
    $values = $res.values

    if ($null -eq $values -or $values.Count -eq 0) {
        return [PSCustomObject]@{
            Header = @()
            Rows = @()
            SiteCount = 0
            ValidKeywordCount = 0
            RawValues = @()
        }
    }

    $header = $values[0]
    $rows = if ($values.Count -gt 1) { $values[1..($values.Count - 1)] } else { @() }

    # Calculate valid keywords count (matching Star characters in KW columns)
    $kwCount = 0
    $starChar = [char]0x2606
    $kwStartCol = 8
    if ($header -is [array]) {
        for ($i = 0; $i -lt $header.Count; $i++) {
            $h = [string]$header[$i]
            if ($h -match "WinningKw1\b" -or $h -match "KW1\b" -or $h.EndsWith("KW1")) {
                $kwStartCol = $i
                break
            }
        }
    }
    foreach ($r in $rows) {
        if ($r -is [array]) {
            $maxCol = [Math]::Min($r.Count, ($kwStartCol + 16))
            for ($c = $kwStartCol; $c -lt $maxCol; $c++) {
                $cell = [string]$r[$c]
                if (-not [string]::IsNullOrWhiteSpace($cell)) {
                    $lines = $cell -split "`r?`n"
                    foreach ($l in $lines) {
                        $t = $l.Trim()
                        if ($t.StartsWith($starChar)) {
                            $kwCount++
                        }
                    }
                }
            }
        }
    }

    return [PSCustomObject]@{
        Header = $header
        Rows = $rows
        SiteCount = $rows.Count
        ValidKeywordCount = $kwCount
        RawValues = $values
    }
}


