<#
.SYNOPSIS
    sheet_atomic_writer.ps1
    Responsibility: Atomically update spreadsheet with pre-validated clean rows.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\sheet_profile_resolver.ps1"

function Update-SheetAtomic {
    param(
        [Parameter(Mandatory=$true)]
        $Rows,

        [Parameter(Mandatory=$false)]
        [string]$SheetId = "",

        [Parameter(Mandatory=$false)]
        [string]$TargetSheetName = "",

        [Parameter(Mandatory=$false)]
        [string]$Token = "",

        [Parameter(Mandatory=$false)]
        [string]$ClearTarget = "A:Y",

        [Parameter(Mandatory=$false)]
        [switch]$AllowHealing = $false,

        [Parameter(Mandatory=$false)]
        [switch]$SkipValidation = $false
    )

    if ([string]::IsNullOrWhiteSpace($SheetId)) {
        $profile = Resolve-SheetProfile
        $SheetId = $profile.SpreadsheetId
    }

    if ([string]::IsNullOrWhiteSpace($TargetSheetName)) {
        # Default: 当たりKW (UTF-8 bytes)
        $TargetSheetName = [System.Text.Encoding]::UTF8.GetString(@(0xE5,0xBD,0x93,0xE3,0x81,0x9F,0xE3,0x82,0x8A,0x4B,0x57))
    }

    # 1. Pre-validation Gate
    if (-not $SkipValidation) {
        . "$PSScriptRoot\guard_normal_state.ps1"
        $eval = Test-NormalStateStandard -SheetRows $Rows -AllowHealing:$AllowHealing
        if (-not $eval.Passed) {
            $errSummary = ($eval.Errors) -join "; "
            throw "Atomic Pre-Validation FAILED: $errSummary. Aborting update."
        }
    }

    # 2. Acquire access token if missing
    if ([string]::IsNullOrWhiteSpace($Token)) {
        . "$PSScriptRoot\sheet_auth_provider.ps1"
        $Token = Get-GoogleAccessToken
    }

    # 3. Prepare payload first (fail-fast before any destructive action)
    $bodyObj = @{
        range = "'$TargetSheetName'!A1"
        majorDimension = "ROWS"
        values = $Rows
    }
    $jsonBody = $bodyObj | ConvertTo-Json -Depth 5
    $utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)

    # 4. Clear target range
    $escapedClearRange = [Uri]::EscapeDataString("'$TargetSheetName'!$ClearTarget")
    $clearUrl = "https://sheets.googleapis.com/v4/spreadsheets/$SheetId/values/$escapedClearRange`:clear"
    Invoke-RestMethod -Uri $clearUrl -Method Post -Headers @{ Authorization = "Bearer $Token" } | Out-Null

    # 5. Write new clean rows
    $escapedWriteRange = [Uri]::EscapeDataString("'$TargetSheetName'!A1")
    $updateUrl = "https://sheets.googleapis.com/v4/spreadsheets/$SheetId/values/$escapedWriteRange`?valueInputOption=USER_ENTERED"

    $headers = @{
        Authorization = "Bearer $Token"
        "Content-Type" = "application/json; charset=utf-8"
    }

    $updateRes = Invoke-RestMethod -Uri $updateUrl -Method Put -Headers $headers -Body $utf8Bytes

    return [PSCustomObject]@{
        Status = "Success"
        UpdatedRows = $updateRes.updatedRows
        UpdatedCells = $updateRes.updatedCells
        Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
}

function Clear-SheetRowAtomic {
    param(
        [Parameter(Mandatory=$true)]
        [int]$RowNumber,

        [Parameter(Mandatory=$false)]
        [string]$SheetId = "",

        [Parameter(Mandatory=$false)]
        [string]$TargetSheetName = "",

        [Parameter(Mandatory=$false)]
        [string]$Token = ""
    )

    if ($RowNumber -le 1) {
        throw "RowNumber must be greater than 1 (header row 1 cannot be cleared)."
    }

    if ([string]::IsNullOrWhiteSpace($SheetId)) {
        $profile = Resolve-SheetProfile
        $SheetId = $profile.SpreadsheetId
    }

    if ([string]::IsNullOrWhiteSpace($TargetSheetName)) {
        $TargetSheetName = [System.Text.Encoding]::UTF8.GetString(@(0xE5,0xBD,0x93,0xE3,0x81,0x9F,0xE3,0x82,0x8A,0x4B,0x57))
    }

    if ([string]::IsNullOrWhiteSpace($Token)) {
        . "$PSScriptRoot\sheet_auth_provider.ps1"
        $Token = Get-GoogleAccessToken
    }

    $clearRange = "A$RowNumber`:Y$RowNumber"
    $escapedClearRange = [Uri]::EscapeDataString("'$TargetSheetName'!$clearRange")
    $clearUrl = "https://sheets.googleapis.com/v4/spreadsheets/$SheetId/values/$escapedClearRange`:clear"
    $res = Invoke-RestMethod -Uri $clearUrl -Method Post -Headers @{ Authorization = "Bearer $Token" }

    return [PSCustomObject]@{
        Status = "Success"
        ClearedRange = $res.clearedRange
        Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
}

function Remove-SheetRowAtomic {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$Predicate,

        [Parameter(Mandatory=$false)]
        [string]$SheetId = "",

        [Parameter(Mandatory=$false)]
        [string]$TargetSheetName = "",

        [Parameter(Mandatory=$false)]
        [string]$Token = "",

        [Parameter(Mandatory=$false)]
        [switch]$AllowHealing = $true
    )

    if ([string]::IsNullOrWhiteSpace($SheetId)) {
        $profile = Resolve-SheetProfile
        $SheetId = $profile.SpreadsheetId
    }

    if ([string]::IsNullOrWhiteSpace($TargetSheetName)) {
        $TargetSheetName = [System.Text.Encoding]::UTF8.GetString(@(0xE5,0xBD,0x93,0xE3,0x81,0x9F,0xE3,0x82,0x8A,0x4B,0x57))
    }

    . "$PSScriptRoot\sheet_data_reader.ps1"
    $sheetData = Read-SheetData -SheetId $SheetId -TargetSheetName $TargetSheetName -Token $Token
    if ($null -eq $sheetData.RawValues -or $sheetData.RawValues.Count -le 1) {
        return [PSCustomObject]@{ Status = "NoRowsToRemove"; RemovedCount = 0 }
    }

    $header = $sheetData.RawValues[0]
    $cleanRows = [System.Collections.Generic.List[object]]::new()
    $cleanRows.Add($header)
    $removedCount = 0

    for ($i = 1; $i -lt $sheetData.RawValues.Count; $i++) {
        $row = $sheetData.RawValues[$i]
        $shouldRemove = & $Predicate $row ($i + 1)
        if ($shouldRemove) {
            $removedCount++
        } else {
            $cleanRows.Add($row)
        }
    }

    if ($removedCount -eq 0) {
        return [PSCustomObject]@{ Status = "NoRowsMatched"; RemovedCount = 0 }
    }

    $res = Update-SheetAtomic -Rows $cleanRows.ToArray() -SheetId $SheetId -TargetSheetName $TargetSheetName -Token $Token -AllowHealing:$AllowHealing
    return [PSCustomObject]@{
        Status = "Success"
        RemovedCount = $removedCount
        RemainingRows = $cleanRows.Count
        UpdatedCells = $res.UpdatedCells
        Timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz")
    }
}



