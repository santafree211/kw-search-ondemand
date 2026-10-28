<#
.SYNOPSIS
    engine_star3_gate.ps1 - 星3先行コミットゲート＆ストック退避モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       芋づる抽出されたKWバッチに「☆☆☆以上（Star3+）」が1件以上含まれているか判定。
       星3が含まれないバッチはスプシ登録せず直接ストック（stock_shelved.json）へ退避し、
       黄金比率（☆☆☆ >= 50%）を崩さない安全なコミットのみを実行する。
    2. 準拠ルール:
       - GEMINI.md 第2条: 黄金比率維持（☆☆☆が全体の過半数を維持、☆☆と☆は各25%以下）。
    3. 入力・出力仕様:
       - Inputs : $HarvestResult, $TargetGenre, $Gender, $Profile, $Tracker, $DryRun
       - Outputs: PSCustomObject @{ Committed (bool), Reason (string) }
    4. 修正時の注意点:
       - 星3が存在しないバッチは例外なくスプシへの行登録を遮断し、ストックファイルに追記すること。
       - コミット時は `tools/sheet_commit.ps1` を正規呼び出しすること。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\portfolio_ratio_balancer.ps1"

function Invoke-Star3FirstCommitGate {
    param(
        [Parameter(Mandatory=$true)]
        $HarvestResult,

        [Parameter(Mandatory=$true)]
        $TargetGenre,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$true)]
        $Profile,

        [Parameter(Mandatory=$true)]
        $Tracker,

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
    )

    $dom = $HarvestResult.Domain
    $cleanUrl = $HarvestResult.CleanUrl
    $da = $HarvestResult.Da
    $siteTitle = $HarvestResult.SiteTitle
    $domainKws = $HarvestResult.DomainKws

    $stockFile = $Profile.StockPath
    $alloc = Get-PortfolioAllocation -CurrentKws $Tracker.ExistingKws -NewKws $domainKws -StockPath $stockFile
    $hasStar3 = (@($domainKws | Where-Object { (Test-KeywordStarType $_) -eq "STAR3_PLUS" }).Count -gt 0)

    $commitKws = @()
    if (-not $hasStar3 -and (-not $alloc.CanCommit -or $alloc.CommitKeywords.Count -eq 0)) {
        Write-Output "    [STAR3-FIRST GATE] No Star3+ discovered in this batch ($($domainKws.Count) KWs). Shelving directly to stock without sheet commit."
        if ($alloc.ShelvedKeywords -and $alloc.ShelvedKeywords.Count -gt 0) {
            $stockDir = Split-Path -Parent $stockFile
            if (-not (Test-Path $stockDir)) { New-Item -ItemType Directory -Path $stockDir -Force | Out-Null }
            [System.IO.File]::WriteAllText($stockFile, ($alloc.ShelvedKeywords | ConvertTo-Json -Depth 5), [System.Text.Encoding]::UTF8)
        }
        return [PSCustomObject]@{
            Committed = $false
            NewKws    = @()
        }
    } else {
        $commitKws = if ($alloc.CanCommit -and $alloc.CommitKeywords.Count -gt 0) { @($alloc.CommitKeywords) } else { @($domainKws) }
    }

    $isCommitted = $false
    if ($commitKws.Count -gt 0) {
        $originKw = $commitKws[0]
        Write-Output "    >>> REAL-TIME SAFE COMMIT: '$siteTitle' ($cleanUrl, DA: $da) with $($commitKws.Count) KWs"

        try {
            $commitScript = "$projectRoot\tools\sheet_commit.ps1"
            $commitParams = @{
                SiteName    = $siteTitle
                Url         = $cleanUrl
                Da          = $da
                OriginKw    = $originKw
                WinningKws  = $commitKws
                Gender      = $Gender
                GenreNumber = $TargetGenre.Id
                GenreName   = $TargetGenre.Name
            }
            if ($DryRun) {
                $commitParams["DryRun"] = $true
            }
            $commitOut = & $commitScript @commitParams
            Write-Output "    Commit Result: $commitOut"

            if (-not $DryRun) {
                $Tracker.RegisteredUrls[$dom] = $true
                $Tracker.ExistingKws += $commitKws
                foreach ($ck in $commitKws) {
                    $cleanCk = $ck -replace "^\s*[\u2605\u2606]+", ""
                    $cleanCk = ($cleanCk -replace $Tracker.ParenPattern, "").Trim()
                    $cTokens = $cleanCk -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                    $normCk = (($cTokens | Sort-Object) -join " ").ToLower()
                    if (-not [string]::IsNullOrWhiteSpace($normCk)) {
                        $Tracker.RegisteredKws[$normCk] = $true
                    }
                }
                $isCommitted = $true
                Write-Output "    [REAL-TIME SUCCESS] Site '$siteTitle' committed to $Gender spreadsheet!"
            } else {
                Write-Output "    [DRY-RUN SUCCESS] Simulated commit passed successfully."
            }
        } catch {
            Write-Warning "Commit error: $_"
        }
    }

    return [PSCustomObject]@{
        Committed = $isCommitted
        NewKws    = $commitKws
    }
}
