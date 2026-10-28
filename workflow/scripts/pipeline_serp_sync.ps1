<#
.SYNOPSIS
    pipeline_serp_sync.ps1 - Google Real SERP突合・0星パージ同期モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SerpApiの利用可能枠を判定し、スプレッドシート上のキーワードをGoogle実測リアルタイムSERPと照合。
       弱席が失われたKW（0星）の自動パージと最新星数の同期を実行する。
    2. 準拠ルール:
       - GEMINI.md 第3条: 実測エビデンスに基づく星数確定（推測値の排除）。
       - SerpApi厳格クォータ管理: 日次上限（7回/日）、月間上限（240回/月）を1コールも超過させない。
    3. 入力・出力仕様:
       - Inputs : $Gender ("both" | "female" | "male"), $MaxCallLimit (int), $DryRun (switch)
       - Outputs: なし（スプシへの直接反映およびコンソールログ）
    4. 修正時の注意点:
       - SerpApi残枠が0以下の場合はリモート検索を行わず安全にスキップすること。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\serpapi_client.ps1"

function Invoke-PipelineSerpSync {
    param(
        [Parameter(Mandatory=$false)]
        [string]$TargetGender = "both",

        [Parameter(Mandatory=$false)]
        [switch]$IsDryRun = $false
    )

    Write-Output "`n----------------------------------------------------------"
    Write-Output ">>> [CYCLE 2-4: SERP & SHEET CLEANUP] Verifying & Purging via Google Real SERP..."
    Write-Output "----------------------------------------------------------"

    $serpConfig = Get-SerpApiConfig
    if (-not [string]::IsNullOrWhiteSpace($serpConfig.api_key)) {
        $serpUsage = Get-SerpApiDailyUsage -DailyLimit $serpConfig.daily_limit -MonthlyLimit $serpConfig.monthly_limit
        if (-not $serpUsage.IsLimitReached -and $serpUsage.RemainingCalls -gt 0) {
            Write-Output "SerpApi available quota: $($serpUsage.RemainingCalls) calls today (Month: $($serpUsage.CallsThisMonth)/$($serpUsage.MonthlyLimit))."
            Write-Output "Running Google real-time SERP verification: Deleting 0-stars, purging dead sites, confirming true stars..."
            $cmdArgs = @(
                "-ExecutionPolicy", "Bypass",
                "-File", "$projectRoot\tools\verify_sheet_serpapi.ps1",
                "-Gender", $TargetGender,
                "-Limit", $serpUsage.RemainingCalls
            )
            if ($IsDryRun) {
                $cmdArgs += "-DryRun"
            }
            try {
                & powershell @cmdArgs
            } catch {
                Write-Warning "SerpApi verification encountered an error: $_"
            }
        } else {
            Write-Output "SerpApi quota currently at limit (Today: $($serpUsage.CallsToday)/$($serpUsage.DailyLimit), Month: $($serpUsage.CallsThisMonth)/$($serpUsage.MonthlyLimit)). Syncing cached SERP evidence..."
            $cmdArgs = @(
                "-ExecutionPolicy", "Bypass",
                "-File", "$projectRoot\tools\verify_sheet_serpapi.ps1",
                "-Gender", $TargetGender,
                "-SyncCached"
            )
            if ($IsDryRun) {
                $cmdArgs += "-DryRun"
            }
            try {
                & powershell @cmdArgs
            } catch {}
        }
    } else {
        Write-Output "SerpApi key not detected in Windows environment. Skipping SERP verification phase."
    }
}
