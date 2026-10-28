<#
.SYNOPSIS
    commit_sheet_state_loader.ps1 - 既存スプシKW抽出・トークンマップ構築モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       スプレッドシートの既存行データ（KW1〜16列）から登録済みKWリストを抽出すると同時に、
       スペース区切り単語をソート結合した正規化トークンマップ（$existingTokenMap）を構築する。
    2. 入力・出力仕様:
       - Inputs : $ExistingRows (シート行配列), $Header (ヘッダー配列)
       - Outputs: PSCustomObject @{ KwStartCol, CurrentKws (string[]), ExistingTokenMap (hashtable) }
    3. 修正時の注意点:
       - 1行内に改行区切りで複数KWが入っているケース（レガシー互換）も漏れなく分解して抽出すること。
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
