<#
.SYNOPSIS
    commit_serp_reconciler.ps1 - コミット前SERP星数実測突合モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       コミット対象のキーワードについて、ローカル生SERPキャッシュ上位10位内の弱競合席数を厳密再計算し、
       KWプレフィックスの星数（例: ☆☆☆）と完全一致しているか照合する。乖離があれば例外をスローして遮断する。
    2. 準拠ルール:
       - GEMINI.md 第3条: 3者突合照合監査と実測エビデンス（スプシ ✕ ルール ✕ Ubersuggest生データの一致）。
    3. 入力仕様:
       - $WinningKws : string[] (例: @("☆☆☆キーワード(5400)"))
       - $Gender     : string ("female" | "male")
    4. 修正時の注意点:
       - 星3以上のKWは弱席数3席以上であれば合致とみなす（☆☆☆以上の上限クランプ互換）。
       - キャッシュ内の弱席数が申告星数と異なる場合は、絶対にコミットを許可してはならない。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\eval_star_calculator.ps1"
. "$PSScriptRoot\eval_star_calculator_male.ps1"
. "$PSScriptRoot\store_api_query.ps1"

function Assert-CommitSerpStarReconciliation {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$WinningKws,

        [Parameter(Mandatory=$true)]
        [string]$Gender
    )

    $isFemale = ($Gender -eq "female")
    $starChar = [char]0x2606
    $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

    foreach ($wKw in $WinningKws) {
        $tKw = ([string]$wKw).Trim()
        $kwStars = 0
        while ($kwStars -lt $tKw.Length -and $tKw[$kwStars] -eq $starChar) { $kwStars++ }
        $cleanKw = $tKw.Substring($kwStars).Trim()
        $vol = 0
        if ($cleanKw -match $parenPattern) {
            $vol = [int]$matches[1]
            $cleanKw = ($cleanKw -replace $parenPattern, "").Trim()
        }

        $arch = Find-ApiArchive -Endpoint "serp_analysis" -TargetKey $cleanKw
        if ($arch -and $arch.Data) {
            $serpEntries = $null
            if ($arch.Data.serpEntries) { $serpEntries = $arch.Data.serpEntries }
            elseif ($arch.Data.serp_table) { $serpEntries = $arch.Data.serp_table }
            elseif ($arch.Data.result -and $arch.Data.result.serp_table) { $serpEntries = $arch.Data.result.serp_table }

            if ($serpEntries) {
                $starEval = if ($isFemale) {
                    Get-StrictStarEvaluation -Keyword $cleanKw -SearchVolume $vol -SerpEntries $serpEntries
                } else {
                    Get-StrictStarEvaluationMale -Keyword $cleanKw -SearchVolume $vol -SerpEntries $serpEntries
                }

                $calcStars = $starEval.StarCount
                $starMatch = ($calcStars -eq $kwStars) -or ($kwStars -ge 3 -and $calcStars -ge 3)
                if (-not $starMatch) {
                    throw "SERP Star Reconciliation Violation for '$cleanKw': Claimed $kwStars stars, but Raw SERP top 10 yields $calcStars weak seats ($($starEval.PureLowDaCount) personal + $($starEval.WeakUgcCount) UGC). Aborting commit."
                }
            }
        }
    }
}
