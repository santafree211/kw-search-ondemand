<#
.SYNOPSIS
    workflow/scripts/sheet_date_tracker.ps1
    Responsibility: Format, validate, and extract survey dates for spreadsheet row linking.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Format-SurveyDate {
    param(
        [Parameter(Mandatory=$false)]
        [string]$RawDate = ""
    )

    if ([string]::IsNullOrWhiteSpace($RawDate)) {
        return (Get-Date).ToString("yyyy-MM-dd")
    }

    # Match YYYY-MM-DD
    if ($RawDate -match "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") {
        return $RawDate
    }

    # Try parse generic date
    $parsedDate = [DateTime]::MinValue
    if ([DateTime]::TryParse($RawDate, [ref]$parsedDate)) {
        return $parsedDate.ToString("yyyy-MM-dd")
    }

    # Default fallback
    return (Get-Date).ToString("yyyy-MM-dd")
}

function Test-SurveyDateFormat {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DateString
    )

    if ($DateString -match "^[0-9]{4}-[0-9]{2}-[0-9]{2}$") {
        return $true
    }
    return $false
}

function Get-RowSurveyKey {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SurveyDate,

        [Parameter(Mandatory=$true)]
        [string]$Keyword
    )

    $cleanDate = Format-SurveyDate -RawDate $SurveyDate
    $cleanKw = $Keyword.Trim()
    return "$cleanDate`::$cleanKw"
}
