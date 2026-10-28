<#
.SYNOPSIS
    commit_sheet_dedup.ps1 - シート内重複および異性シート重複排除モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       コミット予定のKWを正規化形式（例: ☆☆☆KW(Vol)）に整え、現在のスプレッドシートおよび異性シート（男性探索時は女性シート、女性探索時は男性シート）
       との間で完全一致・語順違い重複がないかを厳格に排除する。
    2. 準拠ルール:
       - GEMINI.md 第2条: スプシ行登録の保護（重複KWの混入防止）。
       - Cross-Gender Barrier: 男女シート間での同一KW登録の物理遮断。
    3. 入力・出力仕様:
       - Inputs : $WinningKws (string[]), $ExistingTokenMap (hashtable), $Gender (string)
       - Outputs: string[] (重複が除外されたコミット対象KW配列)
    4. 修正時の注意点:
       - 全候補が重複として弾かれた場合は即座に throw して処理を中断すること。
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
