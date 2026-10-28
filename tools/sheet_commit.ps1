<#
.SYNOPSIS
    tools/sheet_commit.ps1
    Responsibility: Single Unified Safe Site & Keyword Spreadsheet Commit Engine.
    Architecture: Ultra-Lean Orchestrator delegating to specialized single-responsibility modules:
      - commit_param_parser.ps1 (Input normalization, JSON parsing & keyword expansion)
      - commit_policy_guard.ps1 (Site eligibility DA 1-9, non-UGC, gender, YMYL & entertainment guards)
      - commit_serp_reconciler.ps1 (SERP star rating reconciliation with raw API cache)
      - commit_sheet_state_loader.ps1 (Extraction of existing sheet keywords and token map)
      - commit_sheet_dedup.ps1 (Duplicate rejection within sheet and across opposite gender sheet)
      - commit_genre_resolver.ps1 (Strict semantic genre resolution against 50-genre catalog)
      - commit_row_builder.ps1 (Row formatting, site merge, and 16-KW overflow split generation)
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Mandatory=$false)]
    [string]$SiteJsonPath = "",

    [Parameter(Mandatory=$false)]
    [string]$SiteName = "",

    [Parameter(Mandatory=$false)]
    [string]$Url = "",

    [Parameter(Mandatory=$false)]
    [string]$SiteKey = "",

    [Parameter(Mandatory=$false)]
    [int]$Da = 0,

    [Parameter(Mandatory=$false)]
    [string]$OriginKw = "",

    [Parameter(Mandatory=$false)]
    [string[]]$WinningKws = @(),

    [Parameter(Mandatory=$false)]
    [string]$SpreadsheetId = "",

    [Parameter(Mandatory=$false)]
    [string]$Gender = "",

    [Parameter(Mandatory=$false)]
    [string]$SurveyDate = "",

    [Parameter(Mandatory=$false)]
    [string]$GenreNumber = "",

    [Parameter(Mandatory=$false)]
    [string]$GenreName = "",

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false,

    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs = @()
)

$ErrorActionPreference = "Stop"

$isDryRun = ($DryRun -eq $true -or "$DryRun" -match "^(?i:true|1)$" -or ($DryRun -is [System.Management.Automation.SwitchParameter] -and $DryRun.IsPresent))

$projectRoot = Split-Path -Parent $PSScriptRoot
. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"
. "$projectRoot\workflow\scripts\portfolio_ratio_balancer.ps1"
. "$projectRoot\workflow\scripts\guard_normal_state.ps1"
. "$projectRoot\workflow\scripts\sheet_atomic_writer.ps1"
. "$projectRoot\workflow\scripts\sheet_date_tracker.ps1"
. "$projectRoot\workflow\scripts\commit_param_parser.ps1"
. "$projectRoot\workflow\scripts\commit_policy_guard.ps1"
. "$projectRoot\workflow\scripts\commit_serp_reconciler.ps1"
. "$projectRoot\workflow\scripts\commit_sheet_state_loader.ps1"
. "$projectRoot\workflow\scripts\commit_sheet_dedup.ps1"
. "$projectRoot\workflow\scripts\commit_genre_resolver.ps1"
. "$projectRoot\workflow\scripts\commit_row_builder.ps1"

# 1. Parse and normalize input parameters
$parsed = Parse-CommitParameters -SiteJsonPath $SiteJsonPath -SiteName $SiteName -Url $Url -SiteKey $SiteKey -Da $Da -OriginKw $OriginKw -WinningKws $WinningKws -GenreNumber $GenreNumber -GenreName $GenreName -ExtraArgs $ExtraArgs
$SiteName    = $parsed.SiteName
$Url         = $parsed.Url
$Da          = $parsed.Da
$OriginKw    = $parsed.OriginKw
$WinningKws  = $parsed.WinningKws
$GenreNumber = $parsed.GenreNumber
$GenreName   = $parsed.GenreName

$profile = Resolve-SheetProfile -SpreadsheetId $SpreadsheetId -Gender $Gender
$SpreadsheetId = $profile.SpreadsheetId
$stockPath = if (-not [string]::IsNullOrWhiteSpace($profile.StockPath)) { $profile.StockPath } else { "" }
$configDir = Join-Path $projectRoot "workflow\config"

# 2. Enforce site eligibility & policy gates (DA 1-9, Non-UGC, Gender, YMYL, Entertainment)
Assert-CommitSiteAndKeywordPolicy -SiteName $SiteName -Url $Url -Da $Da -OriginKw $OriginKw -WinningKws $WinningKws -Gender $profile.Gender

# 3. Enforce SERP star reconciliation against raw API cache
Assert-CommitSerpStarReconciliation -WinningKws $WinningKws -Gender $profile.Gender

# 4. Read existing spreadsheet state and build token map
$current = Read-SheetData -SheetId $SpreadsheetId
$header = $current.Header
$existingRows = $current.Rows
$surveyDateFormatted = Format-SurveyDate -RawDate $SurveyDate

$sheetState = Get-SheetExistingKeywordsAndTokenMap -ExistingRows $existingRows -Header $header
$kwStartCol = $sheetState.KwStartCol
$currentKws = $sheetState.CurrentKws
$existingTokenMap = $sheetState.ExistingTokenMap

# 5. Deduplicate WinningKws against existing sheet and opposite gender sheet
$WinningKws = Get-DeduplicatedCommitKeywords -WinningKws $WinningKws -ExistingTokenMap $existingTokenMap -Gender $profile.Gender

# 6. Golden Ratio Gate (50:25:25) & Stock Allocation
$alloc = Get-PortfolioAllocation -CurrentKws $currentKws -NewKws $WinningKws -StockPath $stockPath

# Always persist updated shelved stock
if ($alloc.ShelvedKeywords -and $alloc.ShelvedKeywords.Count -gt 0) {
    $dir = Split-Path -Parent $stockPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($stockPath, ($alloc.ShelvedKeywords | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
}

if (-not $alloc.CanCommit -or $alloc.CommitKeywords.Count -eq 0) {
    Write-Warning "Golden Ratio Gate: Incoming keywords would violate 50:25:25 golden ratio (Star3+ >= 50%). Shelved $($WinningKws.Count) keywords to stock ($stockPath) until more Star3+ are discovered."
    return
}

$commitKws = @($alloc.CommitKeywords)
if ($commitKws.Count -eq 0) {
    Write-Warning "No valid winning keywords available to commit."
    return
}

# 7. Strict Semantic Genre Resolution
$resolvedGenre = Resolve-CommitGenre -GenreNumber $GenreNumber -GenreName $GenreName -SiteName $SiteName -CommitKws $commitKws -Gender $profile.Gender -ConfigDir $configDir
$GenreNumber = $resolvedGenre.Id
$GenreName   = $resolvedGenre.Name

# 8. Build updated rows (merge into existing site domain or append new split rows)
$updatedRows = Build-UpdatedSheetRows -Header $header -ExistingRows $existingRows -SiteName $SiteName -Url $Url -Da $Da -GenreNumber $GenreNumber -GenreName $GenreName -CommitKws $commitKws -SurveyDateFormatted $surveyDateFormatted -KwStartCol $kwStartCol

# 9. Pre-validate Normal State
$eval = Test-NormalStateStandard -SheetRows $updatedRows -EnforceUniqueSites -AllowHealing
if (-not $eval.Passed) {
    $errs = $eval.Errors -join "; "
    throw "Pre-validation FAILED: $errs"
}

# 10. Atomic Write (if not dry-run)
$writeRes = $null
if (-not $isDryRun) {
    $writeRes = Update-SheetAtomic -Rows $updatedRows -SheetId $SpreadsheetId -TargetSheetName $profile.TargetSheetName -AllowHealing
    $stockList = if ($alloc.ShelvedKeywords) { @($alloc.ShelvedKeywords) } else { @() }
    $newShelvedJson = $stockList | ConvertTo-Json -Depth 5
    if ([string]::IsNullOrWhiteSpace($newShelvedJson)) { $newShelvedJson = "[]" }
    [System.IO.File]::WriteAllText($stockPath, $newShelvedJson, [System.Text.Encoding]::UTF8)
}

[PSCustomObject]@{
    Status         = if ($isDryRun) { "DryRun_Passed" } else { "Committed" }
    SiteName       = $SiteName
    CommittedKws   = $commitKws
    ShelvedKws     = $alloc.ShelvedKeywords
    TotalKeywords  = $alloc.TotalKeywordsAfter
    ResultingRatio = $alloc.ResultingRatio
    UpdatedCells   = if ($writeRes) { $writeRes.UpdatedCells } else { 0 }
} | ConvertTo-Json -Depth 5
