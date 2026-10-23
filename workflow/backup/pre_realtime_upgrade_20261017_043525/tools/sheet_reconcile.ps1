<#
.SYNOPSIS
    tools/sheet_reconcile.ps1
    Common 3-Way Reconciliation Audit CLI Tool across Sheet, Rule 3/4, and Uber Raw Data.
    Supports Female, Male, and Unified All (Both) execution.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [Alias("Gender")]
    [ValidateSet("all", "both", "female", "male")]
    [string]$Profile = "all",

    [Parameter(Mandatory=$false)]
    [int]$RowNumber = 0,

    [Parameter(Mandatory=$false)]
    [switch]$CheckAllRows = $false,

    [Parameter(Mandatory=$false)]
    [switch]$Json = $false
)

$ErrorActionPreference = "Stop"

$scriptsDir = Join-Path $PSScriptRoot "..\workflow\scripts"
. "$scriptsDir\guard_sheet_reconcile.ps1"

$res = Invoke-Sheet3WayReconciliation -ProfileName $Profile -RowNumber $RowNumber -CheckAllRows:$CheckAllRows -Silent:$true

if ($Json) {
    $res | ConvertTo-Json -Depth 6
    exit 0
}

$starChar = [char]0x2606

function Print-ProfileReport($r) {
    Write-Output "================================================================================"
    Write-Output "               3-WAY RECONCILIATION AUDIT REPORT ($($r.Title))"
    Write-Output "================================================================================"
    Write-Output "Spreadsheet ID : $($r.SpreadsheetId)"
    Write-Output "Target Profile : $($r.Profile)"
    Write-Output "Overall Passed : $(if ($r.OverallPassed) { 'TRUE [ALL RECONCILED]' } else { 'FALSE [ATTENTION REQUIRED]' })"
    Write-Output "Golden Ratio   : Star3+: $($r.GoldenRatio.Star3Percent)% | Star2: $($r.GoldenRatio.Star2Percent)% | Star1: $($r.GoldenRatio.Star1Percent)% (Passed: $($r.GoldenRatioPassed))"
    Write-Output "Audited Rows   : $($r.RowResults.Count) rows"
    Write-Output "Unverified Star KWs (no Google/Uber SERP evidence): $($r.UnverifiedStarKeywords)"
    Write-Output "--------------------------------------------------------------------------------"

    foreach ($rr in $r.RowResults) {
        $statusStr = if ($rr.Passed) { "[PASS] 100% RECONCILED" } else { "[FAIL] VIOLATION FOUND" }
        Write-Output "[$statusStr] Row $($rr.Row): $($rr.SiteName) ($($rr.Domain))"
        Write-Output "  Site Subject  : $(if ($rr.IsPurePersonal) { 'PASS (Pure Personal Blog)' } else { 'FAIL (UGC Platform detected)' })"
        
        $daEvid = if ($null -ne $rr.RawDa) { "$($rr.RawDa) (Raw Uber)" } else { "N/A (Not in local archive)" }
        $daMatchStr = if ($null -eq $rr.DaMatch) { "UNVERIFIED" } elseif ($rr.DaMatch) { "MATCH" } else { "MISMATCH" }
        Write-Output "  DA Alignment  : Sheet DA=$($rr.SheetDa) | Raw DA=$daEvid | Result: $daMatchStr"
        
        Write-Output "  Keywords Audited ($($rr.Keywords.Count)):"
        foreach ($kw in $rr.Keywords) {
            $starDisplay = [string]::new($starChar, $kw.SheetStars)
            $volMatchStr = if ($null -eq $kw.VolumeMatch) { "Unverified" } elseif ($kw.VolumeMatch) { "MATCH" } else { "MISMATCH" }
            $starMatchStr = if ($null -eq $kw.StarMatch) { "Unverified" } elseif ($kw.StarMatch) { "MATCH" } else { "MISMATCH" }
            
            $rawVolStr = if ($null -ne $kw.RawVolume) { "$($kw.RawVolume)" } else { "N/A" }
            $calcSeatsStr = if ($null -ne $kw.CalculatedStars) { "$($kw.CalculatedStars) seats ($($kw.WeakPersonalCount) blog + $($kw.WeakUgcCount) UGC)" } else { "N/A" }
            
            Write-Output "    * '$($kw.Keyword)'"
            Write-Output "      - Stars  : Sheet: $starDisplay ($($kw.SheetStars)) | Raw SERP: $calcSeatsStr | Result: $starMatchStr"
            Write-Output "      - Volume : Sheet: $($kw.SheetVolume) | Raw Cache: $rawVolStr | Result: $volMatchStr"
            if ($kw.SerpRawFile) {
                Write-Output "      - SERP Log: $($kw.SerpRawFile)"
            }
        }

        if ($rr.Violations.Count -gt 0) {
            Write-Output "  Violations ($($rr.Violations.Count)):"
            foreach ($v in $rr.Violations) {
                Write-Output "    - $v"
            }
        }
        Write-Output "--------------------------------------------------------------------------------"
    }

    Write-Output "TOTAL RECONCILIATION VIOLATIONS: $($r.TotalViolations)"
    Write-Output "STATUS: $(if ($r.OverallPassed) { 'PASSED' } else { 'FAILED' })"
    Write-Output "================================================================================`n"
}

if ($res.Profiles) {
    foreach ($p in $res.Profiles) {
        Print-ProfileReport $p
    }
    Write-Output "********************************************************************************"
    Write-Output "OVERALL UNIFIED STATUS: $(if ($res.OverallPassed) { 'ALL PASSED (Female & Male 100% Reconciled)' } else { 'ATTENTION REQUIRED' })"
    Write-Output "********************************************************************************"
} else {
    Print-ProfileReport $res
}
