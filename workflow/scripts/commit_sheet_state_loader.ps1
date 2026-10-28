<#
.SYNOPSIS
    commit_sheet_state_loader.ps1
    Single Responsibility: Extract existing registered keywords and build normalized token map for duplicate prevention.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Get-SheetExistingKeywordsAndTokenMap {
    param(
        [Parameter(Mandatory=$true)]
        $ExistingRows,

        [Parameter(Mandatory=$true)]
        $Header
    )

    $kwStartCol = 6
    for ($i = 0; $i -lt $Header.Count; $i++) {
        $h = [string]$Header[$i]
        if ($h.Contains("KW1")) {
            $kwStartCol = $i
            break
        }
    }

    $currentKws = @()
    $existingTokenMap = @{}
    $starChar = [char]0x2606
    $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

    foreach ($r in $ExistingRows) {
        for ($c = $kwStartCol; $c -lt [Math]::Min($r.Count, ($kwStartCol + 16)); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $lines = $val -split "`r?`n"
                foreach ($l in $lines) {
                    $t = $l.Trim()
                    if ($t.StartsWith($starChar)) {
                        $currentKws += $t
                        $clean = $t -replace "^\s*[\u2605\u2606]+", ""
                        $clean = ($clean -replace $parenPattern, "").Trim()
                        $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        $norm = (($tokens | Sort-Object) -join " ").ToLower()
                        if (-not [string]::IsNullOrWhiteSpace($norm)) {
                            $existingTokenMap[$norm] = $t
                        }
                    }
                }
            }
        }
    }

    return [PSCustomObject]@{
        KwStartCol       = $kwStartCol
        CurrentKws       = $currentKws
        ExistingTokenMap = $existingTokenMap
    }
}
