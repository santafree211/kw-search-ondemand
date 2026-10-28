<#
.SYNOPSIS
    seed_database_sifter.ps1 - ローカルDB適格KW抽出＆ポリシーフィルタモジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       SQLiteの verified_keywords テーブルから、コア単語を含み、かつ serp_cache に未登録の
       高ボリューム（Vol >= 1900）KWを抽出し、YMYL・エンタメ・性別の各ポリシーガードで検証して適格候補を返す。
    2. 準拠ルール:
       - GEMINI.md 第1条: コア単語からのロングテール深掘り。
       - YMYL（健康・医療・金融）、エンタメ（アニメ・ゲーム）、性別不一致KWの物理遮断。
    3. 入力・出力仕様:
       - Inputs : $CoreTokens, $Gender, $MinVolume, $Limit, $ExcludeKeywords, $ExcludeSerpKeywords, $SeenKeywords
       - Outputs: hashtable[] @{ Keyword, Volume, Source = "DB_Verified" }
    4. 修正時の注意点:
       - 既にスプシに登録済みのKW、または既にSERP調査済みのKWは絶対に重複して返さないこと。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\db_sqlite_manager.ps1"
. "$PSScriptRoot\guard_check_gender_kw.ps1"
. "$PSScriptRoot\guard_check_ymyl_kw.ps1"
. "$PSScriptRoot\guard_check_entertainment_kw.ps1"

function Get-UnsearchedGenreDbKeywords {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$CoreTokens,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$false)]
        [int]$MinVolume = 1900,

        [Parameter(Mandatory=$false)]
        [int]$Limit = 10,

        [Parameter(Mandatory=$false)]
        [hashtable]$ExcludeKeywords = @{},

        [Parameter(Mandatory=$false)]
        [System.Collections.Generic.HashSet[string]]$ExcludeSerpKeywords = $null,

        [Parameter(Mandatory=$true)]
        [hashtable]$SeenKeywords
    )

    $derivedKws = @()

    foreach ($token in ($CoreTokens | Select-Object -First 8)) {
        if ($derivedKws.Count -ge $Limit) { break }
        $safeToken = $token.Replace("'", "''")
        $query = "SELECT vk.keyword, vk.volume FROM verified_keywords vk LEFT JOIN serp_cache sc ON vk.keyword = sc.keyword WHERE vk.volume >= $MinVolume AND (vk.gender = '$Gender' OR vk.gender = 'common') AND vk.keyword LIKE '%$safeToken%' AND sc.keyword IS NULL ORDER BY vk.volume DESC LIMIT 20;"
        try {
            $dbRows = @(Invoke-SqliteQuery -SqlQuery $query)
            foreach ($row in $dbRows) {
                if ($derivedKws.Count -ge $Limit) { break }
                $kw = [string]$row.keyword
                if ([string]::IsNullOrWhiteSpace($kw)) { continue }
                if ($SeenKeywords.ContainsKey($kw) -or $ExcludeKeywords.ContainsKey($kw)) { continue }
                if ($null -ne $ExcludeSerpKeywords -and $ExcludeSerpKeywords.Contains($kw)) { continue }

                # Policy safety checks
                $eCheck = Test-KeywordEntertainmentEligibility -Keyword $kw
                if ($eCheck.IsEntertainment) { continue }
                $yCheck = Test-KeywordYmylEligibility -Keyword $kw
                if ($yCheck.IsYmyl) { continue }
                $gCheck = Test-KeywordGenderEligibility -Gender $Gender -Keyword $kw
                if (-not $gCheck.IsAllowed) { continue }

                $SeenKeywords[$kw] = $true
                $derivedKws += @{
                    Keyword = $kw
                    Volume  = [int]$row.volume
                    Source  = "DB_Verified"
                }
            }
        } catch {
            Write-Verbose "DB query error in Seed Database Sifter: $_"
        }
    }

    return $derivedKws
}
