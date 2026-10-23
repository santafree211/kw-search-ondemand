<#
.SYNOPSIS
    workflow/scripts/goal_auto_runner.ps1
    Autonomous Goal Execution Loop: Continues researching and stocking keywords until physical daily limit exhaustion.
    Adheres strictly to Rule 2 (Physical Error Criteria only) and Rule 3 (Normal State 50:25:25 Standard).
    Implementation: 100% Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Continue"

$toolsDir = Join-Path $PSScriptRoot "..\..\tools"
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\research_domain_extract.ps1"
. "$PSScriptRoot\guard_quota_monitor.ps1"
. "$PSScriptRoot\genre_tracker.ps1"

$exhausted = $false
$exhaustionError = ""
$loopCount = 0
$maxLoops = 30

Write-Output "=========================================================="
Write-Output "=== AUTONOMOUS GOAL RUNNER: EXECUTE UNTIL DAILY LIMIT  ==="
Write-Output "=========================================================="
Write-Output "Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

while (-not $exhausted -and $loopCount -lt $maxLoops) {
    $loopCount++
    Write-Output "`n=========================================================="
    Write-Output "--- CYCLE $loopCount / $maxLoops ---"
    Write-Output "=========================================================="

    # 1. Check candidate low-DA personal blogs in discovered_sites
    $pendingSites = Invoke-SqliteQuery -SqlQuery "SELECT domain, site_name, da FROM discovered_sites WHERE status = 'candidate' LIMIT 5;"
    
    if ($null -ne $pendingSites -and $pendingSites.Count -gt 0) {
        foreach ($site in $pendingSites) {
            $dom = [string]$site.domain
            Write-Output "`n[Stage 3 Bulk Domain Infiltration] Infiltrating candidate blog: '$dom' (Limit=1000)..."
            
            try {
                $extRes = Extract-DomainKeywords -Domain $dom -Limit 1000
                Write-Output "  Status: $($extRes.Status)"
                Write-Output "  Total Fetched: $($extRes.TotalFetched) keywords"
                Write-Output "  Tier 1 Qualified (>= 1900): $($extRes.FirstTierCount)"
                Write-Output "  Tier 2 Longtail (< 1900):   $($extRes.LongtailCount)"
                Write-Output "  Top 10 Winning Candidates:  $($extRes.WinningKeywords.Count)"

                # Update status in DB
                $escDom = $dom.Replace("'", "''")
                Invoke-SqliteNonQuery -SqlScript "UPDATE discovered_sites SET status = 'infiltrated' WHERE domain = '$escDom';" | Out-Null
            } catch {
                $errStr = "$_"
                Write-Warning "Domain extraction error on '$dom': $errStr"
                $isEx = Test-ApiExhaustion -ErrorString $errStr
                if ($isEx) {
                    $exhausted = $true
                    $exhaustionError = $errStr
                    Write-Warning "PHYSICAL QUOTA EXHAUSTION DETECTED: $errStr"
                    break
                }
            }
            Start-Sleep -Milliseconds 1000
        }
    } else {
        # 2. If no candidate blogs waiting, run autonomous pipeline for deficit genres
        Write-Output "`n[Autonomous Parallel Discovery] Running balanced genre pipeline for female..."
        try {
            $pipelineScript = Join-Path $toolsDir "female\run_pipeline.ps1"
            $pipeOutput = & powershell -ExecutionPolicy Bypass -File $pipelineScript -BatchSize 2 -MaxBatches 2 -MaxSerpCalls 8 -MaxDomainCalls 3 -Limit 1000
            Write-Output $pipeOutput
        } catch {
            $errStr = "$_"
            Write-Warning "Pipeline error: $errStr"
            $isEx = Test-ApiExhaustion -ErrorString $errStr
            if ($isEx) {
                $exhausted = $true
                $exhaustionError = $errStr
                Write-Warning "PHYSICAL QUOTA EXHAUSTION DETECTED: $errStr"
                break
            }
        }
    }

    if ($exhausted) { break }

    # Sync and inspect pool
    & powershell -ExecutionPolicy Bypass -File (Join-Path $toolsDir "db_pool_inspect.ps1")
    Start-Sleep -Seconds 2
}

Write-Output "`n=========================================================="
Write-Output "=== GOAL EXECUTION LOOP FINISHED ==="
Write-Output "Total Cycles Executed: $loopCount"
Write-Output "Physical Quota Exhausted: $exhausted"
if ($exhausted) {
    Write-Output "Exhaustion Evidence: $exhaustionError"
}
Write-Output "=========================================================="

# Final Quota Audit
& powershell -ExecutionPolicy Bypass -File (Join-Path $toolsDir "guard_inspect_daily_quota.ps1")
