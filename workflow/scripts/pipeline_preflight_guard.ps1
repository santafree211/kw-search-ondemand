<#
.SYNOPSIS
    pipeline_preflight_guard.ps1 - パイプライン実行前API疎通・クォータ事前チェック

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       自律探索ループ開始前に、Ubersuggest等の主要APIへの疎通およびデイリー上限未到達を確認し、
       実行環境が健全であることを保証する。
    2. 準拠ルール:
       - GEMINI.md 第5条: デイリー上限到達時は無駄な空回りをせず安全に待機/停止。
    3. 入力・出力仕様:
       - Inputs : $DryRun (switch)
       - Outputs: PSCustomObject @{ IsHealthy, ErrorMessage }
    4. 修正時の注意点:
       - 429/403/Daily limit reached が検出された場合は即座に IsHealthy=$false を返し、探索ループを起動させないこと。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\research_serp_fetcher.ps1"

function Test-PipelinePreflightHealth {
    param(
        [Parameter(Mandatory=$false)]
        [string]$TestKeyword = "健康 美容"
    )

    Write-Output "`n[Pre-flight Health Check] Testing Ubersuggest API connectivity..."
    $healthCheckRes = Invoke-SerpAnalysisRemote -TargetKeyword $TestKeyword

    if ($null -ne $healthCheckRes -and $healthCheckRes.IsExhausted) {
        Write-Warning "PRE-FLIGHT CHECK FAILED: Ubersuggest API is currently unavailable or exhausted."
        Write-Warning "Error Detail: $($healthCheckRes.Error)"
        return [PSCustomObject]@{
            Passed          = $false
            IsExhausted     = $true
            ExhaustionError = $healthCheckRes.Error
        }
    }

    Write-Output "Pre-flight Health Check Passed: Ubersuggest API is responsive."
    return [PSCustomObject]@{
        Passed          = $true
        IsExhausted     = $false
        ExhaustionError = ""
    }
}
