<#
.SYNOPSIS
    workflow/scripts/guard_check_ymyl_kw.ps1
    Responsibility: Guard against YMYL and Pharmaceutical Law violations (finance, medical, debt, aesthetics, etc.).
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Test-KeywordYmylEligibility {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Keyword = "",

        [Parameter(Mandatory=$false)]
        [string]$RulesPath = ""
    )

    $defaultRules = "c:\Users\santa\OneDrive\prideall\projects\kw-serch\workflow\config\ymyl_exclusion_patterns.json"
    if ([string]::IsNullOrWhiteSpace($RulesPath) -or -not (Test-Path $RulesPath)) {
        if (Test-Path $defaultRules) {
            $RulesPath = $defaultRules
        } else {
            $RulesPath = Join-Path $PSScriptRoot "..\config\ymyl_exclusion_patterns.json"
        }
    }

    $raw = [System.IO.File]::ReadAllText($RulesPath, [System.Text.Encoding]::UTF8)
    $rules = $raw | ConvertFrom-Json

    $cleanKw = $Keyword.Trim()
    # Strip stars and numbers in parentheses if present
    $cleanKw = $cleanKw -replace '^[\*\u2605\u2606]+\s*', '' -replace '[\(\uFF08]\d+[\)\uFF09]$', ''
    $cleanKw = $cleanKw.Trim()

    if ([string]::IsNullOrWhiteSpace($cleanKw)) {
        return [PSCustomObject]@{
            IsYmyl = $false
            IsAllowed = $true
            Keyword = ""
            Category = ""
            CategoryName = ""
            MatchedPattern = ""
            Reason = "Allowed: Empty keyword"
        }
    }

    $categories = $rules.categories.PSObject.Properties
    foreach ($catProp in $categories) {
        $catKey = $catProp.Name
        $catObj = $catProp.Value
        $catName = [string]$catObj.name
        $patterns = $catObj.patterns

        foreach ($p in $patterns) {
            $patStr = [string]$p
            if (-not [string]::IsNullOrWhiteSpace($patStr)) {
                if ($cleanKw.IndexOf($patStr, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    return [PSCustomObject]@{
                        IsYmyl = $true
                        IsAllowed = $false
                        Keyword = $cleanKw
                        Category = $catKey
                        CategoryName = $catName
                        MatchedPattern = $patStr
                        Reason = "BLOCKED by YMYL Guard: Keyword '$cleanKw' matched pattern '$patStr' in category '$catName'."
                    }
                }
            }
        }
    }

    return [PSCustomObject]@{
        IsYmyl = $false
        IsAllowed = $true
        Keyword = $cleanKw
        Category = ""
        CategoryName = ""
        MatchedPattern = ""
        Reason = "Allowed: No YMYL/Medical violation detected."
    }
}

function Test-GenreYmylEligibility {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$GenreObj
    )

    $gName = [string]$GenreObj.name
    $gId = [string]$GenreObj.id

    # Check genre name against YMYL patterns
    $check = Test-KeywordYmylEligibility -Keyword $gName
    if ($check.IsYmyl) {
        return [PSCustomObject]@{
            IsYmyl = $true
            IsAllowed = $false
            GenreId = $gId
            GenreName = $gName
            Reason = "BLOCKED: Genre '$gName' ($gId) is classified as YMYL ($($check.CategoryName))."
        }
    }

    return [PSCustomObject]@{
        IsYmyl = $false
        IsAllowed = $true
        GenreId = $gId
        GenreName = $gName
        Reason = "Allowed: Genre '$gName' is non-YMYL."
    }
}
