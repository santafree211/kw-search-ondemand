<#
.SYNOPSIS
    tools\genre_inspect.ps1
    Responsibility: Inspect progress across 50 article genres (Target: 1,200 keywords each, total 60,000).
    Displays current distribution, ratio compliance per genre, and recommends the next priority genre.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$Gender = "male",

    [Parameter(Mandatory=$false)]
    [switch]$Detailed = $false,

    [Parameter(Mandatory=$false)]
    [int]$TopN = 10
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\workflow\scripts\genre_tracker.ps1"

$report = Get-GenreProgressReport -Gender $Gender

Write-Output "=========================================================="
Write-Output "=== 50-GENRE TARGET PROGRESS (1,200 KW/Genre, 60,000 Total) ==="
Write-Output "=========================================================="
Write-Output "Profile: $($report.Gender) | Sheet: $($report.SheetTitle)"
Write-Output "Total Genres: $($report.TotalGenres) | Target per Genre: $($report.TargetPerGenre)"
Write-Output "Overall Registered KWs: $($report.TotalRegisteredKws) / $($report.OverallTarget) ($($report.OverallProgressPercent)%)"
Write-Output "Completed Genres (1200+): $($report.CompletedGenresCount) / $($report.TotalGenres)"

$wl = $report.WaterLevel
Write-Output "`n[Parallel Water-Leveling (Parallel Progress Status)]"
Write-Output "  Current Milestone Target : All genres to reach $($wl.CurrentMilestone) KWs"
Write-Output "  Milestone Reached Genres : $($wl.MilestoneCompletedGenres) / $($wl.TotalGenres) genres"
Write-Output "  Current Water Level      : Min $($wl.MinKwsPerGenre) KWs | Max $($wl.MaxKwsPerGenre) KWs | Avg $($wl.AvgKwsPerGenre) KWs"
Write-Output "  Equitability Score       : $($wl.EquitabilityScore)% (100% = perfectly balanced)"

if ($report.PriorityBatchGenres.Count -gt 0) {
    Write-Output "`n[Bottom-Up Priority Genres for Immediate Parallel Discovery]"
    $rank = 1
    foreach ($bg in $report.PriorityBatchGenres) {
        Write-Output "  $rank. $($bg.Name) [Current: $($bg.TotalCount)/$($wl.CurrentMilestone) KWs | Deficit: $($wl.CurrentMilestone - $bg.TotalCount)]"
        Write-Output "     Recommended Seeds: $($bg.Seeds -join ', ')"
        $rank++
    }
}

Write-Output "`n--- Top $TopN Under-Represented Genres (Needing Expansion) ---"
$under = @($report.GenreStats | Sort-Object -Property Remaining -Descending | Select-Object -First $TopN)

$formatTable = @()
foreach ($g in $under) {
    $formatTable += [PSCustomObject]@{
        Id = $g.Id
        GenreName = $g.Name
        Progress = "$($g.TotalCount)/$($g.TargetCount)"
        Percent = "$($g.ProgressPercent)%"
        Need = $g.Remaining
        "Ratio (3:2:1)" = "$($g.Star3Count):$($g.Star2Count):$($g.Star1Count)"
    }
}
$formatTable | Format-Table -AutoSize | Out-String | Write-Output

if ($Detailed) {
    Write-Output "=== FULL 50 GENRE CATALOG STATUS ==="
    $allTable = @()
    foreach ($g in $report.GenreStats) {
        $allTable += [PSCustomObject]@{
            Id = $g.Id
            GenreName = $g.Name
            Total = $g.TotalCount
            Need = $g.Remaining
            S3 = $g.Star3Count
            S2 = $g.Star2Count
            S1 = $g.Star1Count
        }
    }
    $allTable | Format-Table -AutoSize | Out-String | Write-Output
}
