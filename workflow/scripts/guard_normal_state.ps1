<#
.SYNOPSIS
    guard_normal_state.ps1
    Responsibility: Enforce strict normal state standard on spreadsheet rows before writing.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\guard_check_entertainment_kw.ps1"

function Test-NormalStateStandard {
    param(
        [Parameter(Mandatory=$true)]
        $SheetRows,
        
        [Parameter(Mandatory=$false)]
        [hashtable]$VolumeMap = $null,

        [Parameter(Mandatory=$false)]
        [switch]$EnforceApiLog = $false,

        [Parameter(Mandatory=$false)]
        [switch]$EnforceUniqueKeywords = $false,

        [Parameter(Mandatory=$false)]
        [switch]$EnforceUniqueSites = $false,

        [Parameter(Mandatory=$false)]
        [switch]$AllowHealing = $false,

        [Parameter(Mandatory=$false)]
        [string]$CachePath = ""
    )

    if ([string]::IsNullOrWhiteSpace($CachePath)) {
        $CachePath = Join-Path $PSScriptRoot "..\data\verified_volume_cache.json"
    }

    # Load cache ONLY if EnforceApiLog is set or VolumeMap is provided
    if ($EnforceApiLog -and $null -eq $VolumeMap -and (Test-Path $CachePath)) {
        $VolumeMap = @{}
        $cacheText = [System.IO.File]::ReadAllText($CachePath, [System.Text.Encoding]::UTF8)
        $parsedCache = $cacheText | ConvertFrom-Json
        if ($parsedCache -is [array]) {
            foreach ($item in $parsedCache) {
                if ($item.Keyword -and $null -ne $item.Volume) {
                    $VolumeMap[$item.Keyword] = [int]$item.Volume
                }
            }
        } elseif ($parsedCache.verified_volumes) {
            foreach ($prop in $parsedCache.verified_volumes.PSObject.Properties) {
                if ($prop.Name -and $null -ne $prop.Value) {
                    $VolumeMap[$prop.Name] = [int]$prop.Value
                }
            }
        } elseif ($parsedCache.SyncRoot) {
            foreach ($item in $parsedCache.SyncRoot) {
                if ($item.Keyword -and $null -ne $item.Volume) {
                    $VolumeMap[$item.Keyword] = [int]$item.Volume
                }
            }
        }
    }

    $errors = @()
    $winningKws = @()
    $siteCount = 0

    $headerRow = $SheetRows[0]
    $siteCol = 3
    $urlCol = 4
    $daCol = 5
    $kwStartCol = 6

    $txtSiteName = [System.Text.Encoding]::UTF8.GetString(@(0xE3,0x82,0xB5,0xE3,0x82,0xA4,0xE3,0x83,0x88,0xE5,0x90,0x8D))
    $foundKw = $false

    for ($i = 0; $i -lt $headerRow.Count; $i++) {
        $hText = [string]$headerRow[$i]
        if ($hText -match "SiteName" -or $hText.Contains($txtSiteName)) { 
            $siteCol = $i 
        }
        elseif ($hText -match "\bURL\b" -or $hText.EndsWith("URL") -or $hText -eq "Url") { 
            $urlCol = $i 
        }
        elseif ($hText -match "^DA$" -or $hText -match "DomainAuthority") { 
            $daCol = $i 
        }
        elseif (-not $foundKw -and ($hText -match "KW1\b" -or $hText -match "WinningKw1\b" -or $hText.EndsWith("KW1"))) { 
            $kwStartCol = $i
            $foundKw = $true
        }
    }

    $starChar = [char]0x2606
    $starBlack = [char]0x2605
    # UTF-8 bytes for Japanese "該当無し"
    $naText = [System.Text.Encoding]::UTF8.GetString(@(0xE8,0xA9,0xB2,0xE5,0xBD,0x93,0xE7,0x84,0xA1,0xE3,0x81,0x97))

    $seenKeywords = @{}
    $seenSites = @{}
    $seenDomains = @{}

    for ($r = 1; $r -lt $SheetRows.Count; $r++) {
        $row = $SheetRows[$r]
        $rowNum = $r + 1
        $site = if ($row.Count -gt $siteCol) { [string]$row[$siteCol] } else { "" }
        $kw1 = if ($row.Count -gt $kwStartCol) { [string]$row[$kwStartCol] } else { "" }

        # 1. Empty row check
        if ([string]::IsNullOrWhiteSpace($site) -and [string]::IsNullOrWhiteSpace($kw1)) {
            if ($r -lt ($SheetRows.Count - 1)) {
                $errors += "Row $rowNum : Empty row found in middle."
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($kw1) -or $kw1 -eq $naText) {
            $errors += "Row $rowNum ($site): Winning KW is empty or N/A."
        }

        # 1.2 Status column corruption check
        $rowStatus = if ($row.Count -gt 0) { [string]$row[0] } else { "" }
        if ($rowStatus.Contains([char]0x9132)) { # 鄲
            $errors += "Row $rowNum : Status contains corrupted character (登鄲完了): '$rowStatus'."
        }

        # 1.3 Genre ID validation
        $genreId = if ($row.Count -gt 1) { ([string]$row[1]).Trim() } else { "" }
        if (-not ($genreId -match "^[MF]-\d{2}$")) {
            $errors += "Row $rowNum ($site): Invalid or missing Genre ID: '$genreId' (must match M-xx or F-xx)."
        }

        # 1.4 Star summary corruption check (Col 22)
        $starSummary = if ($row.Count -gt 22) { [string]$row[22] } else { "" }
        if ($starSummary.Contains("eMax") -or $starSummary.Contains([char]0x7B9D)) { # 箝
            $errors += "Row $rowNum ($site): Corrupted Star summary display: '$starSummary'."
        }

        # 1.5 Site and Domain Uniqueness check
        $siteUrl = if ($row.Count -gt $urlCol) { ([string]$row[$urlCol]).Trim() } else { "" }
        if ($EnforceUniqueSites -and (-not [string]::IsNullOrWhiteSpace($siteUrl))) {
            $cleanUrl = $siteUrl.ToLower().TrimEnd('/')
            $domain = ""
            try {
                $uri = [System.Uri]$siteUrl
                $domain = $uri.Host.ToLower().Trim()
                if ($domain.StartsWith("www.")) { $domain = $domain.Substring(4) }
            } catch {
                $domain = $cleanUrl
            }

            if (-not [string]::IsNullOrWhiteSpace($cleanUrl)) {
                if ($seenSites.ContainsKey($cleanUrl)) {
                    if ($seenSites[$cleanUrl] -ne ($rowNum - 1)) {
                        $errors += "Duplicate Site URL: '$siteUrl' at Row $rowNum is already registered at Row $($seenSites[$cleanUrl])."
                    } else {
                        $seenSites[$cleanUrl] = $rowNum
                    }
                } else {
                    $seenSites[$cleanUrl] = $rowNum
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($domain)) {
                if ($seenDomains.ContainsKey($domain)) {
                    if ($seenDomains[$domain] -ne ($rowNum - 1)) {
                        $errors += "Duplicate Site Domain: '$domain' at Row $rowNum is already registered at Row $($seenDomains[$domain])."
                    } else {
                        $seenDomains[$domain] = $rowNum
                    }
                } else {
                    $seenDomains[$domain] = $rowNum
                }
            }
        }

        $siteCount++

        for ($c = $kwStartCol; $c -lt [Math]::Min($row.Count, ($kwStartCol + 16)); $c++) {
            $val = [string]$row[$c]
            if ([string]::IsNullOrWhiteSpace($val)) { continue }

            $lines = $val -split "`r?`n"
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

                # 2. Black star check
                if ($trimmed.StartsWith($starBlack)) {
                    $errors += "Row $rowNum Col $([char](65+$c)): Contains black star garbage: '$trimmed'."
                }

                # 3. Star evaluation
                $type = "OTHER"
                if ($trimmed.StartsWith("$starChar$starChar$starChar")) { $type = "STAR3_PLUS" }
                elseif ($trimmed.StartsWith("$starChar$starChar")) { $type = "STAR2" }
                elseif ($trimmed.StartsWith($starChar)) { $type = "STAR1" }
                else {
                    $errors += "Row $rowNum Col $([char](65+$c)): Invalid star format: '$trimmed'."
                }

                # 4. Volume format check (>= 1900)
                $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"
                if ($trimmed -match $parenPattern) {
                    $vol = [int]$matches[1]
                    if ($vol -lt 1900) {
                        $errors += "Row $rowNum Col $([char](65+$c)): Volume below 1900: '$trimmed' (Vol: $vol)."
                    }
                } else {
                    $errors += "Row $rowNum Col $([char](65+$c)): No volume found in '$trimmed'."
                }

                $cleanKw = $trimmed -replace "^\s*[\u2605\u2606]+", ""
                $cleanKw = ($cleanKw -replace $parenPattern, "").Trim()

                # 5. Verified Volume Map Cross-Check
                if ($null -ne $VolumeMap) {
                    if (-not $VolumeMap.ContainsKey($cleanKw)) {
                        $errors += "Row $rowNum Col $([char](65+$c)): Unverified keyword without API log: '$cleanKw'."
                    } else {
                        $actualVol = $VolumeMap[$cleanKw]
                        if ($actualVol -lt 1900) {
                            $errors += "Row $rowNum Col $([char](65+$c)): Verified volume below 1900: '$cleanKw' (Actual: $actualVol)."
                        }
                    }
                }

                # 6. Duplicate Winning Keyword Check (Exact and Token-Permutation Uniqueness)
                if ($EnforceUniqueKeywords) {
                    $tokens = $cleanKw -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $normKw = (($tokens | Sort-Object) -join " ").ToLower()
                    if ($seenKeywords.ContainsKey($normKw)) {
                        $prev = $seenKeywords[$normKw]
                        $errors += "Row $($rowNum) Col $([char](65+$c)): Duplicate winning keyword '$cleanKw' (already appears at Row $($prev.Row) Col $($prev.Col))."
                    } else {
                        $seenKeywords[$normKw] = @{ Row = $rowNum; Col = [char](65+$c); Site = $site }
                    }
                }

                # 5.5 Entertainment / Fiction / Local / Yakuza Guard
                $entCheck = Test-KeywordEntertainmentEligibility -Keyword $cleanKw
                if ($entCheck.IsEntertainment) {
                    $errors += "Row $rowNum Col $([char](65+$c)): Entertainment / Local / Anti-Social Violation: '$cleanKw' matched '$($entCheck.MatchedPattern)' ($($entCheck.CategoryName))."
                }

                $winningKws += [PSCustomObject]@{
                    Row = $rowNum
                    Col = [char](65 + $c)
                    Text = $trimmed
                    Type = $type
                }
            }
        }
    }

    # 6. Overall Ratio Check
    $totalKw = $winningKws.Count
    $star3Count = 0
    $star2Count = 0
    $star1Count = 0
    $star3Pct = 0
    $star2Pct = 0
    $star1Pct = 0

    if ($totalKw -eq 0) {
        $errors += "No winning keywords found."
    } else {
        $star3Count = @($winningKws | Where-Object { $_.Type -eq "STAR3_PLUS" }).Count
        $star2Count = @($winningKws | Where-Object { $_.Type -eq "STAR2" }).Count
        $star1Count = @($winningKws | Where-Object { $_.Type -eq "STAR1" }).Count

        $star3Pct = [Math]::Round(($star3Count / $totalKw) * 100, 1)
        $star2Pct = [Math]::Round(($star2Count / $totalKw) * 100, 1)
        $star1Pct = [Math]::Round(($star1Count / $totalKw) * 100, 1)

        # 1. Star3+ must be at least 50.0%
        if ($star3Pct -lt 50.0) {
            if ($AllowHealing) {
                Write-Warning "Healing mode: Star3+ ratio is currently $star3Pct% (below 50.0%), allowing healing commits towards recovery."
            } else {
                $errors += "Star3+ ratio is $star3Pct% (must be >= 50.0%)."
            }
        }

        # 2. Discrete Golden Ratio Balance (Star2 & Star1):
        # Maximum allowed for Star2 and Star1 is floor(Star3 / 2), and their counts must be balanced within +/- 1.
        $maxWeak = [int][Math]::Floor($star3Count / 2)
        if ($star2Count -gt $maxWeak) {
            if (-not $AllowHealing) {
                $errors += "Star2 count ($star2Count) exceeds maximum capacity ($maxWeak) based on Star3 count ($star3Count)."
            }
        }
        if ($star1Count -gt $maxWeak) {
            if (-not $AllowHealing) {
                $errors += "Star1 count ($star1Count) exceeds maximum capacity ($maxWeak) based on Star3 count ($star3Count)."
            }
        }
        if ([Math]::Abs($star2Count - $star1Count) -gt 1) {
            if (-not $AllowHealing) {
                $errors += "Star2 ($star2Count) and Star1 ($star1Count) are imbalanced (difference must be <= 1)."
            }
        }
    }

    $isPassed = ($errors.Count -eq 0)

    return [PSCustomObject]@{
        Passed = $isPassed
        Errors = $errors
        SiteCount = $siteCount
        TotalKeywords = $totalKw
        Star3Count = $star3Count
        Star2Count = $star2Count
        Star1Count = $star1Count
        Star3Percent = $star3Pct
        Star2Percent = $star2Pct
        Star1Percent = $star1Pct
    }
}


