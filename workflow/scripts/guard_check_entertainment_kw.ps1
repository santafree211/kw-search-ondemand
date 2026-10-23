<#
.SYNOPSIS
    workflow/scripts/guard_check_entertainment_kw.ps1
    Responsibility: Guard against non-evergreen entertainment (novels, books, anime, manga, spoilers, movies, games).
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Test-KeywordEntertainmentEligibility {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Keyword = "",

        [Parameter(Mandatory=$false)]
        [string]$RulesPath = ""
    )

    $defaultRules = "c:\Users\santa\OneDrive\prideall\projects\kw-serch\workflow\config\entertainment_exclusion_patterns.json"
    if ([string]::IsNullOrWhiteSpace($RulesPath) -or -not (Test-Path $RulesPath)) {
        if (Test-Path $defaultRules) {
            $RulesPath = $defaultRules
        } else {
            $RulesPath = Join-Path $PSScriptRoot "..\config\entertainment_exclusion_patterns.json"
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
            IsEntertainment = $false
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
                        IsEntertainment = $true
                        IsAllowed = $false
                        Keyword = $cleanKw
                        Category = $catKey
                        CategoryName = $catName
                        MatchedPattern = $patStr
                        Reason = "BLOCKED by Entertainment Guard: Keyword '$cleanKw' matched pattern '$patStr' in category '$catName'."
                    }
                }
            }
        }
    }

    return [PSCustomObject]@{
        IsEntertainment = $false
        IsAllowed = $true
        Keyword = $cleanKw
        Category = ""
        CategoryName = ""
        MatchedPattern = ""
        Reason = "Allowed: No entertainment/fiction violation detected."
    }
}
