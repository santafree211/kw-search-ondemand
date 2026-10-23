<#
.SYNOPSIS
    workflow/scripts/genre_tracker.ps1
    Responsibility: Track progress of 50 article genres (Target: 200 KWs/genre, 10,000 total).
    Maintains 50:25:25 golden ratio per genre and balances discovery across all genres.
    Supports dynamic genre discovery from new specialized personal blogs.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\sheet_profile_resolver.ps1"
. "$PSScriptRoot\sheet_data_reader.ps1"
. "$PSScriptRoot\portfolio_ratio_balancer.ps1"

function Get-GenreCatalog {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Gender = "male",

        [Parameter(Mandatory=$false)]
        [string]$CatalogPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
        $cleanGender = if ($Gender) { $Gender.Trim().ToLower() } else { "male" }
        if ($cleanGender -eq "f" -or $cleanGender -eq "women") { $cleanGender = "female" }
        if ($cleanGender -eq "m" -or $cleanGender -eq "men") { $cleanGender = "male" }
        $candidate = Join-Path $PSScriptRoot "..\config\genre_catalog_$cleanGender.json"
        if (Test-Path $candidate) {
            $CatalogPath = $candidate
        } else {
            $CatalogPath = Join-Path $PSScriptRoot "..\config\genre_catalog.json"
        }
    }

    if (-not (Test-Path $CatalogPath)) {
        throw "Genre catalog not found at: $CatalogPath"
    }

    $raw = [System.IO.File]::ReadAllText($CatalogPath, [System.Text.Encoding]::UTF8)
    return ($raw | ConvertFrom-Json)
}

function Save-GenreCatalog {
    param(
        [Parameter(Mandatory=$true)]
        $CatalogObj,

        [Parameter(Mandatory=$false)]
        [string]$Gender = "male",

        [Parameter(Mandatory=$false)]
        [string]$CatalogPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
        $cleanGender = if ($Gender) { $Gender.Trim().ToLower() } else { "male" }
        $CatalogPath = Join-Path $PSScriptRoot "..\config\genre_catalog_$cleanGender.json"
    }

    $json = $CatalogObj | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($CatalogPath, $json, [System.Text.Encoding]::UTF8)
}

function Get-GenreProgressReport {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Gender = "male",

        [Parameter(Mandatory=$false)]
        [string]$CatalogPath = ""
    )

    $profile = Resolve-SheetProfile -Gender $Gender
    if ([string]::IsNullOrWhiteSpace($CatalogPath) -and $profile.GenreCatalogPath -and (Test-Path $profile.GenreCatalogPath)) {
        $CatalogPath = $profile.GenreCatalogPath
    }
    $catalog = Get-GenreCatalog -Gender $Gender -CatalogPath $CatalogPath
    $profile = Resolve-SheetProfile -Gender $Gender
    $sheetData = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName

    # Extract keywords per row and map by genre number if available
    $genreKwsMap = @{}
    $allSheetKws = @()
    $kwStartCol = 8
    for ($i = 0; $i -lt $sheetData.Header.Count; $i++) {
        $h = [string]$sheetData.Header[$i]
        if ($h -match "WinningKw1\b" -or $h -match "KW1\b" -or $h.EndsWith("KW1")) {
            $kwStartCol = $i
            break
        }
    }

    foreach ($r in $sheetData.Rows) {
        $rGenreNo = if ($r.Count -gt 1) { ([string]$r[1]).Trim() } else { "" }
        $rowKws = @()
        $maxCol = [Math]::Min($r.Count, ($kwStartCol + 16))
        for ($c = $kwStartCol; $c -lt $maxCol; $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $lines = $val -split "`r?`n"
                foreach ($l in $lines) {
                    $t = $l.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($t)) {
                        $allSheetKws += $t
                        $rowKws += $t
                    }
                }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($rGenreNo)) {
            if (-not $genreKwsMap.ContainsKey($rGenreNo)) {
                $genreKwsMap[$rGenreNo] = @()
            }
            $genreKwsMap[$rGenreNo] += $rowKws
        }
    }

    # Analyze genre distribution
    $targetPerGenre = [int]$catalog.target_per_genre
    $genreStats = @()
    $unclassifiedKws = @()

    foreach ($g in $catalog.genres) {
        $gId = [string]$g.id
        $gName = [string]$g.name
        $seeds = @($g.seeds)

        # Match keywords to genre: first check explicit genre number from sheet
        $matchedKws = @()
        if ($genreKwsMap.ContainsKey($gId)) {
            $matchedKws = @($genreKwsMap[$gId])
        }


        # Count star levels
        $s3 = @($matchedKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR3_PLUS" }).Count
        $s2 = @($matchedKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR2" }).Count
        $s1 = @($matchedKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR1" }).Count
        $total = $matchedKws.Count

        $p3 = if ($total -gt 0) { [Math]::Round(($s3 / $total) * 100, 1) } else { 0 }
        $p2 = if ($total -gt 0) { [Math]::Round(($s2 / $total) * 100, 1) } else { 0 }
        $p1 = if ($total -gt 0) { [Math]::Round(($s1 / $total) * 100, 1) } else { 0 }

        $remaining = [Math]::Max(0, ($targetPerGenre - $total))
        $progressPct = [Math]::Round(($total / $targetPerGenre) * 100, 1)

        $genreStats += [PSCustomObject]@{
            Id = $gId
            Name = $gName
            TotalCount = $total
            TargetCount = $targetPerGenre
            ProgressPercent = $progressPct
            Remaining = $remaining
            Star3Count = $s3
            Star2Count = $s2
            Star1Count = $s1
            Star3Percent = $p3
            Star2Percent = $p2
            Star1Percent = $p1
            Seeds = $seeds
            IsCompleted = ($total -ge $targetPerGenre)
        }
    }

    # 4. Calculate Water-Leveling (Parallel Progress) Metrics
    $counts = @($genreStats | ForEach-Object { [int]$_.TotalCount })
    $meas = $counts | Measure-Object -Minimum -Maximum -Average
    $minCount = [int]$meas.Minimum
    $maxCount = [int]$meas.Maximum
    $avgCount = [Math]::Round([double]$meas.Average, 1)

    # Determine current synchronization milestone
    $milestoneTargets = @(3, 5, 10, 20, 50, 100, 200)
    $currentMilestone = 200
    foreach ($m in $milestoneTargets) {
        if ($minCount -lt $m) {
            $currentMilestone = $m
            break
        }
    }

    $milestoneCompletedCount = @($genreStats | Where-Object { $_.TotalCount -ge $currentMilestone }).Count

    # Calculate Equitability Score (100% = perfectly balanced)
    $equitabilityScore = 100.0
    if ($maxCount -gt 0) {
        $spread = $maxCount - $minCount
        $equitabilityScore = [Math]::Max(0.0, [Math]::Round(100.0 - (($spread / [Math]::Max(1, $maxCount)) * 50.0), 1))
    }

    # Sort priority: lowest total count first (strictly bottom-up water-filling)
    $priorityList = @($genreStats | Where-Object { $_.TotalCount -lt $currentMilestone } | Sort-Object -Property TotalCount, Remaining -Descending:$false)
    if ($priorityList.Count -eq 0) {
        $priorityList = @($genreStats | Where-Object { -not $_.IsCompleted } | Sort-Object -Property TotalCount)
    }

    $totalRegistered = $allSheetKws.Count
    $overallTarget = $catalog.genres.Count * $targetPerGenre

    return [PSCustomObject]@{
        Gender = $profile.Gender
        SheetTitle = $profile.Title
        TotalGenres = $catalog.genres.Count
        TargetPerGenre = $targetPerGenre
        OverallTarget = $overallTarget
        TotalRegisteredKws = $totalRegistered
        OverallProgressPercent = [Math]::Round(($totalRegistered / $overallTarget) * 100, 2)
        CompletedGenresCount = @($genreStats | Where-Object { $_.IsCompleted }).Count
        WaterLevel = [PSCustomObject]@{
            MinKwsPerGenre = $minCount
            MaxKwsPerGenre = $maxCount
            AvgKwsPerGenre = $avgCount
            CurrentMilestone = $currentMilestone
            MilestoneCompletedGenres = $milestoneCompletedCount
            TotalGenres = $catalog.genres.Count
            EquitabilityScore = $equitabilityScore
        }
        RecommendedNextGenre = if ($priorityList.Count -gt 0) { $priorityList[0] } else { $null }
        PriorityBatchGenres = if ($priorityList.Count -gt 0) { @($priorityList | Select-Object -First 3) } else { @() }
        GenreStats = $genreStats
    }
}

function Get-NextBalancedGenreSeeds {
    param(
        [Parameter(Mandatory=$false)]
        [string]$Gender = "male",

        [Parameter(Mandatory=$false)]
        [int]$MaxGenres = 3,

        [Parameter(Mandatory=$false)]
        [string]$CatalogPath = ""
    )

    $report = Get-GenreProgressReport -Gender $Gender -CatalogPath $CatalogPath
    $targetGenres = @($report.PriorityBatchGenres | Select-Object -First $MaxGenres)

    $recommendedSeeds = @()
    foreach ($g in $targetGenres) {
        foreach ($s in $g.Seeds) {
            if (-not ($recommendedSeeds -contains $s)) {
                $recommendedSeeds += $s
            }
        }
    }

    return [PSCustomObject]@{
        Gender = $Gender
        CurrentMilestone = $report.WaterLevel.CurrentMilestone
        TargetGenres = @($targetGenres | ForEach-Object { "$($_.Name) (Current: $($_.TotalCount)/$($report.WaterLevel.CurrentMilestone))" })
        Seeds = $recommendedSeeds
    }
}

function Add-DynamicGenre {
    param(
        [Parameter(Mandatory=$true)]
        [string]$GenreId,

        [Parameter(Mandatory=$true)]
        [string]$GenreName,

        [Parameter(Mandatory=$false)]
        [string[]]$Seeds = @(),

        [Parameter(Mandatory=$false)]
        [string]$CatalogPath = ""
    )

    $catalog = Get-GenreCatalog -CatalogPath $CatalogPath
    $existing = @($catalog.genres | Where-Object { $_.id -eq $GenreId })
    if ($existing.Count -gt 0) {
        Write-Output "Genre '$GenreId' already exists in catalog. Skipping."
        return $catalog
    }

    $newGenre = [PSCustomObject]@{
        id = $GenreId
        name = $GenreName
        seeds = $Seeds
    }

    $catalog.genres += $newGenre
    Save-GenreCatalog -CatalogObj $catalog -CatalogPath $CatalogPath
    Write-Output "Dynamic Genre Successfully Added: '$GenreName' (ID: $GenreId). Total Genres: $($catalog.genres.Count)"
    return $catalog
}
