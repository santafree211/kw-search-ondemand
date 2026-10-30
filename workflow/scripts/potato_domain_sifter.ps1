<#
.SYNOPSIS
    potato_domain_sifter.ps1 - 個人ブログ流入キーワード機械的抽出・精査モジュール (Pure ASCII)
.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SKILL.md (potato_digging_research) ステップ2に完全準拠。
       起点個人ブログに対して Ubersuggest API 'domain_keywords' を実行し、
       Google検索順位 1〜10位、かつ月間検索ボリューム 1,900以上のオーガニックKWを機械的に抽出する。
    2. 準拠ルール:
       - GEMINI.md 第3条: 月間ボリューム1,900以上の生データのみ有効。
       - guard_check_entertainment_kw.ps1 による娯楽・マンガ除外。
       - guard_check_ymyl_kw.ps1 によるYMYL除外。
    3. 入力・出力仕様:
       - Get-PotatoBlogTopKeywords:
           - Inputs : [string]$Domain, [string]$Gender, [hashtable]$RegisteredKws, [switch]$DryRun
           - Outputs: PSCustomObject @{
               Domain, TotalFound, FilteredKeywords, ApiCallsMade, IsExhausted, ExhaustionError
             }
    4. 禁止事項:
       - AI推測でのボリューム付与禁止。API生レスポンスの search_volume / position のみを厳格適用。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"
. "$PSScriptRoot\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\research_domain_harvester.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"

function Get-PotatoBlogTopKeywords {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Domain,

        [Parameter(Mandatory=$false)]
        [string]$Gender = "both",

        [Parameter(Mandatory=$false)]
        [hashtable]$RegisteredKws = @{},

        [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
    )

    $dom = $Domain.ToLower().Trim()
    $apiCallsMade = 0
    $isExhausted = $false
    $exhaustionError = ""
    $filteredKws = @()

    Write-Output "    >>> [POTATO STEP 2] Harvesting Google 1-10 organic keywords for '$dom'..."

    # DryRun モードのハンドリング
    if ($DryRun) {
        Write-Output "    [DryRun] domain_keywords API call skipped for '$dom'."
        return [PSCustomObject]@{
            Domain           = $dom
            TotalFound       = 0
            FilteredKeywords = @()
            ApiCallsMade     = 0
            IsExhausted      = $false
            ExhaustionError  = ""
        }
    }

    # Ubersuggest domain_keywords 実行
    $dRes = Extract-DomainKeywords -Domain $dom -MinVolume 1900 -MaxPosition 10 -Limit 30
    if ($null -ne $dRes) {
        if ($dRes.IsExhausted) {
            return [PSCustomObject]@{
                Domain           = $dom
                TotalFound       = 0
                FilteredKeywords = @()
                ApiCallsMade     = 1
                IsExhausted      = $true
                ExhaustionError  = $dRes.ExhaustionError
            }
        }

        $apiCallsMade = 1
        $rawKws = $dRes.WinningKeywords

        if ($rawKws -and $rawKws.Count -gt 0) {
            foreach ($kwItem in $rawKws) {
                $kw = [string]$kwItem.Keyword
                $vol = [int]$kwItem.SearchVolume
                $pos = [int]$kwItem.Position

                # 1. 検索ボリューム >= 1900 かつ 順位 1〜10位
                if ($vol -lt 1900 -or $pos -lt 1 -or $pos -gt 10) { continue }

                # 2. 登録済み重複チェック
                $cleanKw = $kw.ToLower().Trim()
                if ($RegisteredKws -and $RegisteredKws.ContainsKey($cleanKw)) { continue }

                # 3. ノイズ・娯楽除外チェック
                $entCheck = Test-KeywordEntertainmentEligibility -Keyword $kw
                if ($entCheck.IsEntertainment) { continue }

                # 4. YMYL除外チェック
                $ymylCheck = Test-KeywordYmylEligibility -Keyword $kw
                if ($ymylCheck.IsYmyl) { continue }

                $filteredKws += [PSCustomObject]@{
                    Keyword      = $kw
                    SearchVolume = $vol
                    Position     = $pos
                    Domain       = $dom
                }
            }
        }
    }

    Write-Output "    -> '$dom' yields $($filteredKws.Count) eligible candidate keywords (Vol >= 1900, Pos <= 10)."

    return [PSCustomObject]@{
        Domain           = $dom
        TotalFound       = $filteredKws.Count
        FilteredKeywords = $filteredKws
        ApiCallsMade     = $apiCallsMade
        IsExhausted      = $isExhausted
        ExhaustionError  = $exhaustionError
    }
}
