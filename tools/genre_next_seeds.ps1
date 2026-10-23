<#
.SYNOPSIS
    tools/genre_next_seeds.ps1
    Responsibility: Retrieve next underrepresented genres and their seeds for gender-specific balanced research.
    Usage:
        powershell -ExecutionPolicy Bypass -File tools/genre_next_seeds.ps1 -Gender male -Limit 5
        powershell -ExecutionPolicy Bypass -File tools/genre_next_seeds.ps1 -Gender female -Limit 5
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("male", "female", "m", "f", "men", "women")]
    [string]$Gender = "male",

    [Parameter(Mandatory=$false)]
    [int]$Limit = 5
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\workflow\scripts\genre_tracker.ps1"

$report = Get-GenreProgressReport -Gender $Gender

Write-Host "==========================================================================" -ForegroundColor Cyan
Write-Host "   NEXT UNDERREPRESENTED GENRES TO RESEARCH ($($report.Gender.ToUpper()) / BALANCED ROTATION)    " -ForegroundColor Cyan
Write-Host "==========================================================================" -ForegroundColor Cyan

$batch = @($report.PriorityBatchGenres | Select-Object -First $Limit)

if ($null -eq $batch -or $batch.Count -eq 0) {
    Write-Host "All genres are well-balanced or fully stocked!" -ForegroundColor Green
    return
}

$rank = 1
foreach ($g in $batch) {
    $wl = $report.WaterLevel
    $pct = [Math]::Round(($g.TotalCount / $report.TargetPerGenre) * 100, 1)
    $deficit = [Math]::Max(0, ($wl.CurrentMilestone - $g.TotalCount))
    
    Write-Host "`n$rank. [$($g.Id)] $($g.Name)" -ForegroundColor Yellow
    Write-Host "   Current: $($g.TotalCount) / $($wl.CurrentMilestone) KWs (Milestone Deficit: $deficit | Overall: $pct%)" -ForegroundColor White
    Write-Host "   Recommended Seeds for Stage 1:" -ForegroundColor Cyan
    foreach ($s in $g.Seeds) {
        Write-Host "     - '$s'" -ForegroundColor Gray
    }
    $rank++
}

Write-Host "`n==========================================================================" -ForegroundColor Cyan
Write-Host "Tip: Run research pipeline with these seeds to balance $($report.Gender) underrepresented genres." -ForegroundColor DarkGray
Write-Host "==========================================================================" -ForegroundColor Cyan
