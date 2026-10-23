<#
.SYNOPSIS
    workflow/scripts/guard_check_gender_kw.ps1
    Responsibility: Guard against cross-gender keywords (e.g. women cosmetics in male sheet, men grooming in female sheet).
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Test-KeywordGenderEligibility {
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("male", "female", "m", "f", "men", "women")]
        [string]$Gender,

        [Parameter(Mandatory=$false)]
        [string]$Keyword = "",

        [Parameter(Mandatory=$false)]
        [string]$RulesPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($Keyword)) {
        return [PSCustomObject]@{
            IsAllowed = $false
            TargetGender = $Gender
            Keyword = ""
            ForbiddenMatched = "EMPTY_KEYWORD"
            Reason = "Keyword is null or empty"
        }
    }

    $cleanGender = $Gender.Trim().ToLower()
    if ($cleanGender -eq "m" -or $cleanGender -eq "men") { $cleanGender = "male" }
    if ($cleanGender -eq "f" -or $cleanGender -eq "women") { $cleanGender = "female" }

    $defaultRules = "c:\Users\santa\OneDrive\prideall\projects\kw-serch\workflow\config\gender_exclusion_patterns.json"
    if ([string]::IsNullOrWhiteSpace($RulesPath) -or -not (Test-Path $RulesPath)) {
        if (Test-Path $defaultRules) {
            $RulesPath = $defaultRules
        } else {
            $RulesPath = Join-Path $PSScriptRoot "..\config\gender_exclusion_patterns.json"
        }
    }

    $raw = [System.IO.File]::ReadAllText($RulesPath, [System.Text.Encoding]::UTF8)
    $rules = $raw | ConvertFrom-Json

    $forbiddenList = if ($cleanGender -eq "male") {
        $rules.male_sheet_forbidden
    } else {
        $rules.female_sheet_forbidden
    }

    $cleanKw = $Keyword.Trim()
    # Strip stars and numbers in parentheses if present
    $cleanKw = $cleanKw -replace '^[\*\u2605\u2606]+\s*', '' -replace '[\(\uFF08]\d+[\)\uFF09]$', ''
    $cleanKw = $cleanKw.Trim()

    foreach ($forbidden in $forbiddenList) {
        if ($cleanKw.IndexOf($forbidden, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return [PSCustomObject]@{
                IsAllowed = $false
                TargetGender = $cleanGender
                Keyword = $cleanKw
                ForbiddenPattern = $forbidden
                Reason = "Keyword '$cleanKw' contains forbidden cross-gender pattern '$forbidden' for $cleanGender sheet."
            }
        }
    }

    return [PSCustomObject]@{
        IsAllowed = $true
        TargetGender = $cleanGender
        Keyword = $cleanKw
        ForbiddenPattern = ""
        Reason = "Allowed: No cross-gender violation detected."
    }
}
