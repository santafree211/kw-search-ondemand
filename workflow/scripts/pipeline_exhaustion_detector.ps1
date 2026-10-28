<#
.SYNOPSIS
    pipeline_exhaustion_detector.ps1 - バッチ出力ログのAPI物理枯渇/一時遅延分類判定

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       実行された探索バッチの出力ログテキストを解析し、「物理的API上限（429/403/Daily report limit）」と
       「一時的なネットワーク遅延/タイムアウト」を厳格に分類・判定する。
    2. 準拠ルール:
       - GEMINI.md 第3条・第5条: 客観的停止基準の遵守。
       - 一時的通信タイムアウトはMCPリトライ基盤で自己修復を図り、安易な主観的中断を禁止。
    3. 入力・出力仕様:
       - Inputs : $OutputLines (string[] 出力行リスト), $CurrentGender (string)
       - Outputs: PSCustomObject @{ IsPhysicalLimit, IsTransient, ErrorText }
    4. 修正時の注意点:
       - 単なるWarningやTimeout文字列を即座にIsPhysicalLimit=$trueと誤判定しないこと。429/403/Daily report limitの物理的シグナルのみを枯渇と認定すること。
#>

$ErrorActionPreference = "Stop"

function Test-BatchExhaustionStatus {
    param(
        [Parameter(Mandatory=$false)]
        [string[]]$OutputLines = @(),

        [Parameter(Mandatory=$false)]
        [string]$CurrentGender = ""
    )

    $outText = if ($OutputLines) { $OutputLines -join "`n" } else { "" }
    $isBatchExhausted = $false
    $candErr = ""

    if ($outText -match "PHYSICAL API EXHAUSTION DETECTED:\s*(.+)") {
        $candErr = $matches[1].Trim()
        $isBatchExhausted = $true
    } elseif ($outText -match "Physical Exhausted\s*:\s*True") {
        if ($outText -match "Exhaustion (?:Reason|Evidence)\s*:\s*(.+)") {
            $candErr = $matches[1].Trim()
        } else {
            $candErr = "Physical exhaustion reported by batch runner."
        }
        $isBatchExhausted = $true
    }

    $isPhysicalLimit = $false
    $isTransient = $false

    if ($isBatchExhausted) {
        if ($candErr -match "(?i)daily report.*limit|HTTP 429|HTTP 403|quota is exhausted") {
            $isPhysicalLimit = $true
            Write-Warning "Physical API exhaustion verified during $CurrentGender batch: $candErr"
        } elseif ($candErr -match "(?i)timed out|rate limited|temporarily unavailable") {
            $isTransient = $true
            Write-Warning "Transient API timeout/rate limit encountered during $CurrentGender batch. Allowing circuit breaker / retry: '$candErr'"
        } else {
            Write-Warning "False exhaustion trigger ignored: '$candErr'"
        }
    }

    return [PSCustomObject]@{
        IsExhausted     = $isBatchExhausted
        IsPhysicalLimit = $isPhysicalLimit
        IsTransient     = $isTransient
        ErrorText       = $candErr
    }
}
