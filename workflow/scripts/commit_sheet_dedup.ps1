<#
.SYNOPSIS
    commit_sheet_dedup.ps1
    Single Responsibility: Deduplicate and canonicalize proposed winning keywords against existing sheet and opposite gender sheet.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\sheet_cross_gender_guard.ps1"

function Get-DeduplicatedCommitKeywords {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$WinningKws,

        [Parameter(Mandatory=$true)]
        [hashtable]$ExistingTokenMap,

        [Parameter(Mandatory=$true)]
        [string]$Gender
    )

    $starChar = [char]0x2606
    $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"
    $dedupedWinningKws = @()

    foreach ($wk in $WinningKws) {
        $tWk = ([string]$wk).Trim()
        $kwStars = 0
        while ($kwStars -lt $tWk.Length -and $tWk[$kwStars] -eq $starChar) { $kwStars++ }
        $clean = $tWk.Substring($kwStars).Trim()
        $vol = 0
        if ($clean -match $parenPattern) {
            $vol = [int]$matches[1]
            $clean = ($clean -replace $parenPattern, "").Trim()
        }
        # Enforce canonical format: ☆☆☆KW(Vol)
        $starPrefix = [string]::new($starChar, $kwStars)
        $canonicalWk = if ($vol -gt 0) { "$starPrefix$clean($vol)" } else { $tWk }

        $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $norm = (($tokens | Sort-Object) -join " ").ToLower()

        if ($ExistingTokenMap.ContainsKey($norm)) {
            Write-Warning "Commit guard: Rejecting duplicate keyword '$canonicalWk' (already registered as '$($ExistingTokenMap[$norm])')."
        } else {
            # Cross-Gender Barrier: Reject if keyword exists in opposite sheet
            $crossCheck = Test-IsCrossGenderDuplicate -Keyword $clean -CurrentGender $Gender
            if ($crossCheck.IsDuplicate) {
                Write-Warning "Cross-Gender Commit Guard: Rejecting duplicate '$canonicalWk' (already registered in $($crossCheck.OppositeGender) sheet as '$($crossCheck.ExistingKeyword)')."
            } else {
                $dedupedWinningKws += $canonicalWk
                $ExistingTokenMap[$norm] = $canonicalWk
            }
        }
    }

    if ($dedupedWinningKws.Count -eq 0) {
        throw "Cannot commit: All proposed winning keywords already exist in the spreadsheet."
    }

    return $dedupedWinningKws
}
