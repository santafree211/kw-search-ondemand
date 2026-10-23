<#
.SYNOPSIS
    workflow/scripts/sheet_cross_gender_guard.ps1
    Responsibility: Cross-gender keyword deduplication and validation guard.
    Features:
      1. Loads keywords from both sheets (Male & Female) and canonicalizes them.
      2. Normalizes keywords (token-sort + lowercase) to catch word-order variations (e.g. 'セリア 履歴書' vs '履歴書 セリア').
      3. Caches sheet keywords to avoid redundant Google Sheets API calls.
      4. Provides Test-CrossGenderDuplicate to verify if a keyword is already taken in the opposite sheet.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\sheet_profile_resolver.ps1"
. "$PSScriptRoot\sheet_data_reader.ps1"

$global:CrossGenderCache = @{
    Timestamp = [DateTime]::MinValue
    MaleKeywords = @{}
    FemaleKeywords = @{}
    TTLSeconds = 120
}

function Get-CanonicalKeywordKey([string]$Keyword) {
    if ([string]::IsNullOrWhiteSpace($Keyword)) { return "" }
    $clean = $Keyword -replace "^\s*[\u2605\u2606]+", ""
    $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"
    $clean = ($clean -replace $parenPattern, "").Trim()
    $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($tokens.Count -eq 0) { return "" }
    return (($tokens | Sort-Object) -join " ").ToLower()
}

function Update-CrossGenderKeywordCache([switch]$Force) {
    $now = [DateTime]::UtcNow
    $elapsed = ($now - $global:CrossGenderCache.Timestamp).TotalSeconds
    if (-not $Force -and $elapsed -lt $global:CrossGenderCache.TTLSeconds -and $global:CrossGenderCache.MaleKeywords.Count -gt 0) {
        return
    }

    $starChar = [char]0x2606
    $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

    # Helper to extract from sheet data
    $extractKws = {
        param($sheetData, [int]$kwStartCol)
        $map = @{}
        if ($null -eq $sheetData -or $null -eq $sheetData.Rows) { return $map }
        foreach ($r in $sheetData.Rows) {
            for ($c = $kwStartCol; $c -lt [Math]::Min($r.Count, ($kwStartCol + 16)); $c++) {
                $val = [string]$r[$c]
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $lines = $val -split "`r?`n"
                    foreach ($l in $lines) {
                        $t = $l.Trim()
                        if ($t.StartsWith($starChar)) {
                            $key = Get-CanonicalKeywordKey -Keyword $t
                            if (-not [string]::IsNullOrWhiteSpace($key)) {
                                $map[$key] = $t
                            }
                        }
                    }
                }
            }
        }
        return $map
    }

    try {
        $mProf = Resolve-SheetProfile -Gender "male"
        $mData = Read-SheetData -SheetId $mProf.SpreadsheetId -TargetSheetName $mProf.TargetSheetName
        $global:CrossGenderCache.MaleKeywords = & $extractKws $mData $mProf.KwStartCol
    } catch {
        if ($env:KW_SEARCH_VERBOSE -eq "1") {
            [System.Console]::Error.WriteLine("[CROSS-GENDER GUARD WARNING] Could not refresh male sheet keywords: $($_.Exception.Message)")
        }
    }

    try {
        $fProf = Resolve-SheetProfile -Gender "female"
        $fData = Read-SheetData -SheetId $fProf.SpreadsheetId -TargetSheetName $fProf.TargetSheetName
        $global:CrossGenderCache.FemaleKeywords = & $extractKws $fData $fProf.KwStartCol
    } catch {
        if ($env:KW_SEARCH_VERBOSE -eq "1") {
            [System.Console]::Error.WriteLine("[CROSS-GENDER GUARD WARNING] Could not refresh female sheet keywords: $($_.Exception.Message)")
        }
    }

    $global:CrossGenderCache.Timestamp = $now
}

function Get-CrossGenderKeywordMap([string]$TargetGender = "both") {
    Update-CrossGenderKeywordCache
    if ($TargetGender -eq "male") {
        return $global:CrossGenderCache.MaleKeywords
    } elseif ($TargetGender -eq "female") {
        return $global:CrossGenderCache.FemaleKeywords
    } else {
        $combined = @{}
        foreach ($k in $global:CrossGenderCache.MaleKeywords.Keys) { $combined[$k] = $global:CrossGenderCache.MaleKeywords[$k] }
        foreach ($k in $global:CrossGenderCache.FemaleKeywords.Keys) { $combined[$k] = $global:CrossGenderCache.FemaleKeywords[$k] }
        return $combined
    }
}

function Test-IsCrossGenderDuplicate {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$true)]
        [ValidateSet("male", "female")]
        [string]$CurrentGender
    )

    Update-CrossGenderKeywordCache
    $normKey = Get-CanonicalKeywordKey -Keyword $Keyword
    if ([string]::IsNullOrWhiteSpace($normKey)) {
        return @{ IsDuplicate = $false; ExistingKeyword = ""; OppositeGender = "" }
    }

    $oppositeGender = if ($CurrentGender -eq "male") { "female" } else { "male" }
    $oppositeMap = if ($oppositeGender -eq "male") { $global:CrossGenderCache.MaleKeywords } else { $global:CrossGenderCache.FemaleKeywords }

    if ($oppositeMap.ContainsKey($normKey)) {
        return @{
            IsDuplicate = $true
            ExistingKeyword = $oppositeMap[$normKey]
            OppositeGender = $oppositeGender
            CanonicalKey = $normKey
        }
    }

    return @{
        IsDuplicate = $false
        ExistingKeyword = ""
        OppositeGender = $oppositeGender
        CanonicalKey = $normKey
    }
}
