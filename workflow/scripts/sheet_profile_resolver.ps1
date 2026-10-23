<#
.SYNOPSIS
    workflow/scripts/sheet_profile_resolver.ps1
    Responsibility: Resolve spreadsheet metadata, profile, stock paths, and rules based on profile JSONs.
    Supports 100% isolated parallel execution between Male and Female research threads without parameter collisions.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Resolve-SheetProfile {
    param(
        [Parameter(Mandatory=$false)]
        [string]$ProfileName = "",

        [Parameter(Mandatory=$false)]
        [string]$SpreadsheetId = "",

        [Parameter(Mandatory=$false)]
        [string]$Gender = ""
    )

    $femaleId = "1qzhyI8HYRsTyPTyaK7Xnka7PlKAuc3UxpPEaJXj1qTw"
    $maleId   = "1ZFYMVVc10cZISofcB71x6ICt9ejZyGLzmVgpKbXvR40"

    $cleanProf = if ($ProfileName) { $ProfileName.Trim().ToLower() } else { "" }
    $cleanGender = if ($Gender) { 
        $Gender.Trim().ToLower() 
    } elseif ($env:KW_SEARCH_GENDER) {
        $env:KW_SEARCH_GENDER.Trim().ToLower()
    } else { 
        "" 
    }
    $cleanId = if ($SpreadsheetId) { $SpreadsheetId.Trim() } else { "" }

    $targetProfile = ""

    if ($cleanProf -eq "female" -or $cleanProf -eq "f" -or $cleanProf -eq "women") {
        $targetProfile = "female"
    } elseif ($cleanProf -eq "male" -or $cleanProf -eq "m" -or $cleanProf -eq "men") {
        $targetProfile = "male"
    } elseif ($cleanId -eq $femaleId -or $cleanGender -eq "female" -or $cleanGender -eq "f" -or $cleanGender -eq "women") {
        $targetProfile = "female"
    } elseif ($cleanId -eq $maleId -or $cleanGender -eq "male" -or $cleanGender -eq "m" -or $cleanGender -eq "men") {
        $targetProfile = "male"
    } else {
        # Default profile if not specified
        $targetProfile = "female"
    }

    $configDir = Join-Path $PSScriptRoot "..\config"
    $configFile = Join-Path $configDir "profile_$targetProfile.json"

    if (Test-Path $configFile) {
        $raw = [System.IO.File]::ReadAllText($configFile, [System.Text.Encoding]::UTF8)
        $p = $raw | ConvertFrom-Json
        $dataDir = Join-Path $PSScriptRoot "..\data"
        $scriptDir = $PSScriptRoot

        return [PSCustomObject]@{
            Profile = $p.profile
            Gender = $p.gender
            Title = $p.title
            SpreadsheetId = $p.spreadsheetId
            TargetSheetName = $p.targetSheetName
            WeakPatternsPath = (Join-Path $dataDir $p.weakPatternsFile)
            StockPath = (Join-Path $dataDir $p.shelvedStockFile)
            PipelineStatePath = (Join-Path $dataDir $p.pipelineStateFile)
            StarCalculatorScript = (Join-Path $scriptDir $p.starCalculatorScript)
            WeakCompetitorScript = (Join-Path $scriptDir $p.weakCompetitorScript)
            GenreCatalogPath = if ($p.genreCatalogFile) { (Join-Path $configDir $p.genreCatalogFile) } else { (Join-Path $configDir "genre_catalog_$($p.profile).json") }
            KwStartCol = 8
            IsFemale = ($p.profile -eq "female")
            IsMale = ($p.profile -eq "male")
        }
    }

    # Fallback if config missing
    $stockFile = if ($targetProfile -eq "female") { "shelved_stock_female.json" } else { "shelved_stock_male.json" }
    $stateFile = if ($targetProfile -eq "female") { "pipeline_state_female.json" } else { "pipeline_state_male.json" }
    $catFile   = if ($targetProfile -eq "female") { "genre_catalog_female.json" } else { "genre_catalog_male.json" }
    $title = if ($targetProfile -eq "female") { "（女性）KWagent" } else { "KWagent" }
    $resolvedId = if ($targetProfile -eq "female") { $femaleId } else { $maleId }

    return [PSCustomObject]@{
        Profile = $targetProfile
        Gender = $targetProfile
        Title = $title
        SpreadsheetId = $resolvedId
        TargetSheetName = "当たりKW"
        WeakPatternsPath = (Join-Path $PSScriptRoot "..\data\weak_competitor_patterns.json")
        StockPath = (Join-Path $PSScriptRoot "..\data\$stockFile")
        PipelineStatePath = (Join-Path $PSScriptRoot "..\data\$stateFile")
        GenreCatalogPath = (Join-Path $PSScriptRoot "..\config\$catFile")
        StarCalculatorScript = (Join-Path $PSScriptRoot "eval_star_calculator.ps1")
        WeakCompetitorScript = (Join-Path $PSScriptRoot "eval_weak_competitor_rule.ps1")
        KwStartCol = 8
        IsFemale = ($targetProfile -eq "female")
        IsMale = ($targetProfile -eq "male")
    }
}
