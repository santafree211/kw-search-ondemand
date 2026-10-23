<#
.SYNOPSIS
    portfolio_ratio_balancer.ps1
    Responsibility: Balance winning keywords across spreadsheet to satisfy 50%:25%:25% golden ratio.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

$ErrorActionPreference = "Stop"

function Test-KeywordStarType($kw) {
    if ($null -eq $kw) { return "UNKNOWN" }
    if ($kw -is [PSCustomObject] -or $kw -is [hashtable]) {
        if ($kw.StarCount) {
            $sc = [int]$kw.StarCount
            if ($sc -ge 3) { return "STAR3_PLUS" }
            elseif ($sc -eq 2) { return "STAR2" }
            elseif ($sc -eq 1) { return "STAR1" }
        }
        if ($kw.FormattedValue) { $kw = [string]$kw.FormattedValue }
        elseif ($kw.Keyword) { $kw = [string]$kw.Keyword }
    }
    $trimmed = ([string]$kw).Trim()
    $starChar = [char]0x2606
    if ($trimmed.StartsWith("$starChar$starChar$starChar")) { return "STAR3_PLUS" }
    elseif ($trimmed.StartsWith("$starChar$starChar")) { return "STAR2" }
    elseif ($trimmed.StartsWith($starChar)) { return "STAR1" }
    return "UNKNOWN"
}

function Get-PortfolioAllocation {
    param(
        [string[]]$CurrentKws,
        [string[]]$NewKws,
        [string]$StockPath = ""
    )

    if ([string]::IsNullOrWhiteSpace($StockPath)) {
        $StockPath = Join-Path $PSScriptRoot "..\data\shelved_stock.json"
    }

    # 1. Load existing shelved stock safely as string array
    $shelved = @()
    if (Test-Path $StockPath) {
        $stockText = [System.IO.File]::ReadAllText($StockPath, [System.Text.Encoding]::UTF8)
        $parsed = $stockText | ConvertFrom-Json
        if ($parsed -is [array]) {
            foreach ($item in $parsed) {
                if (-not [string]::IsNullOrWhiteSpace([string]$item)) {
                    $shelved += [string]$item
                }
            }
        } elseif ($null -ne $parsed) {
            $shelved += [string]$parsed
        }
    }

    # 2. Count current spreadsheet keywords by star type
    $cStar3 = @($CurrentKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR3_PLUS" }).Count
    $cStar2 = @($CurrentKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR2" }).Count
    $cStar1 = @($CurrentKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR1" }).Count

    # 3. Separate new incoming keywords by star type
    $newStar3 = @($NewKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR3_PLUS" })
    $newStar2 = @($NewKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR2" })
    $newStar1 = @($NewKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR1" })

    $commitKws = @()
    $newShelved = @($shelved)

    # 4. Always accept all Star3+ keywords unconditionally
    foreach ($k in $newStar3) { $commitKws += $k }

    # 5. Calculate maximum allowable weak competitors (Star2 & Star1) based on total Star3+
    # Golden ratio requirement: Star3+ >= 50%, Star2 <= 25%, Star1 <= 25%
    # Discrete formula: Total Star2 <= Floor(Total Star3 / 2), Total Star1 <= Floor(Total Star3 / 2)
    $maxStar3Total = $cStar3 + $newStar3.Count
    $allowedMaxWeak = [int][Math]::Floor($maxStar3Total / 2)
    $availSlots2 = [Math]::Max(0, ($allowedMaxWeak - $cStar2))
    $availSlots1 = [Math]::Max(0, ($allowedMaxWeak - $cStar1))

    # 6. Allocate from new keywords first
    $added2 = 0
    foreach ($k in $newStar2) {
        if ($added2 -lt $availSlots2) {
            $commitKws += $k
            $added2++
        } else {
            $newShelved += $k
        }
    }

    $added1 = 0
    foreach ($k in $newStar1) {
        if ($added1 -lt $availSlots1) {
            $commitKws += $k
            $added1++
        } else {
            $newShelved += $k
        }
    }

    # 7. If capacity still remains AND NOT in healing mode, dequeue allowable keywords from existing shelved stock
    $currentTotal = $CurrentKws.Count
    $curR3Raw = if ($currentTotal -gt 0) { ($cStar3 / $currentTotal) } else { 1.0 }

    $remSlots2 = $availSlots2 - $added2
    $remSlots1 = $availSlots1 - $added1

    if ($remSlots2 -gt 0 -or $remSlots1 -gt 0) {
        $stockStar2 = [System.Collections.Generic.List[string]]::new()
        $stockStar1 = [System.Collections.Generic.List[string]]::new()
        $stockOther = [System.Collections.Generic.List[string]]::new()

        foreach ($sItem in $newShelved) {
            $sType = Test-KeywordStarType $sItem
            if ($sType -eq "STAR2") { $stockStar2.Add($sItem) }
            elseif ($sType -eq "STAR1") { $stockStar1.Add($sItem) }
            else { $stockOther.Add($sItem) }
        }

        # Dequeue in balanced pairs or single slots up to available capacity
        while (($remSlots2 -gt 0 -and $stockStar2.Count -gt 0) -or ($remSlots1 -gt 0 -and $stockStar1.Count -gt 0)) {
            $pulled = $false
            if ($remSlots2 -gt 0 -and $stockStar2.Count -gt 0) {
                # Check that adding Star2 does not create imbalance > 1
                $curDiff = ($cStar2 + $added2 + 1) - ($cStar1 + $added1)
                if ($curDiff -le 1 -or $remSlots1 -gt 0) {
                    $item2 = $stockStar2[0]
                    $stockStar2.RemoveAt(0)
                    $commitKws += $item2
                    $added2++
                    $remSlots2--
                    $pulled = $true
                }
            }
            if ($remSlots1 -gt 0 -and $stockStar1.Count -gt 0) {
                $curDiff = ($cStar1 + $added1 + 1) - ($cStar2 + $added2)
                if ($curDiff -le 1 -or $remSlots2 -gt 0) {
                    $item1 = $stockStar1[0]
                    $stockStar1.RemoveAt(0)
                    $commitKws += $item1
                    $added1++
                    $remSlots1--
                    $pulled = $true
                }
            }
            if (-not $pulled) { break }
        }

        $newShelved = @($stockStar2) + @($stockStar1) + @($stockOther)
    }

    # 8. Balance Star2 and Star1 difference if needed (difference must be <= 1)
    while ([Math]::Abs(($cStar2 + $added2) - ($cStar1 + $added1)) -gt 1) {
        if (($cStar2 + $added2) -gt ($cStar1 + $added1) -and $added2 -gt 0) {
            $added2--
            $removed = $commitKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR2" } | Select-Object -Last 1
            $commitKws = @($commitKws | Where-Object { $_ -ne $removed })
            $newShelved += $removed
        } elseif (($cStar1 + $added1) -gt ($cStar2 + $added2) -and $added1 -gt 0) {
            $added1--
            $removed = $commitKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR1" } | Select-Object -Last 1
            $commitKws = @($commitKws | Where-Object { $_ -ne $removed })
            $newShelved += $removed
        } else {
            break
        }
    }

    # 9. Deduplicate shelved stock safely
    $seenMap = @{}
    $uniqueShelved = @()
    foreach ($sk in $newShelved) {
        $str = ([string]$sk).Trim()
        if (-not [string]::IsNullOrWhiteSpace($str) -and -not $seenMap.ContainsKey($str) -and -not ($commitKws -contains $sk)) {
            $seenMap[$str] = $true
            $uniqueShelved += $str
        }
    }
    $newShelved = $uniqueShelved

    # Calculate final simulated counts
    $finalTotal = $CurrentKws.Count + $commitKws.Count
    $fStar3 = $cStar3 + @($commitKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR3_PLUS" }).Count
    $fStar2 = $cStar2 + @($commitKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR2" }).Count
    $fStar1 = $cStar1 + @($commitKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR1" }).Count

    $r3 = if ($finalTotal -gt 0) { [Math]::Round(($fStar3 / $finalTotal) * 100, 1) } else { 0 }
    $r2 = if ($finalTotal -gt 0) { [Math]::Round(($fStar2 / $finalTotal) * 100, 1) } else { 0 }
    $r1 = if ($finalTotal -gt 0) { [Math]::Round(($fStar1 / $finalTotal) * 100, 1) } else { 0 }

    $curR3 = if ($currentTotal -gt 0) { [Math]::Round(($cStar3 / $currentTotal) * 100, 1) } else { 0 }

    $fMaxWeak = [int][Math]::Floor($fStar3 / 2)
    $isStandardValid = ($r3 -ge 50.0 -and $fStar2 -le $fMaxWeak -and $fStar1 -le $fMaxWeak -and [Math]::Abs($fStar2 - $fStar1) -le 1)

    # Healing Phase: If sheet is currently recovering from ratio dip (e.g. spoiler row relocation),
    # allow commit if it actively improves the Star3+ percentage towards 50%.
    $isHealingValid = $false
    if (-not $isStandardValid -and $curR3Raw -lt 0.50) {
        $hasNewStar3 = (@($commitKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR3_PLUS" }).Count -gt 0)
        $newR3Raw = if ($finalTotal -gt 0) { ($fStar3 / $finalTotal) } else { 0 }
        if ($hasNewStar3 -and ($newR3Raw -gt $curR3Raw -or $newR3Raw -ge 0.50)) {
            $isHealingValid = $true
        }
    }

    $isRatioValid = ($isStandardValid -or $isHealingValid)

    return [PSCustomObject]@{
        CanCommit = $isRatioValid
        IsHealing = $isHealingValid
        CommitKeywords = $commitKws
        ShelvedKeywords = $newShelved
        TotalKeywordsAfter = $finalTotal
        ResultingRatio = [PSCustomObject]@{
            Star3Percent = $r3
            Star2Percent = $r2
            Star1Percent = $r1
        }
    }
}


