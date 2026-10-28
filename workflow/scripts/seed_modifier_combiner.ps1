<#
.SYNOPSIS
    seed_modifier_combiner.ps1 - シードトークン分解＆ロングテール候補合成モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       ジャンル定義シードおよびジャンル名からヘッド単語（headTerms）を抽出し、固定修飾子（おすすめ、選び方等）
       ＋日次AI修飾子（ai_daily_modifiers.json）＋Google Autocomplete（無料サジェスト）を掛け合わせて
       高確率な合成シードリストを生成する。
    2. 準拠ルール:
       - GEMINI.md 第4条: 日次1回AIシード思考プロトコル（0トークン実行時コストの外部修飾子適用）。
    3. 入力・出力仕様:
       - Inputs : $GenreObj (ジャンルオブジェクト), $ConfigDir (設定ディレクトリパス)
       - Outputs: PSCustomObject @{ CandidateSeeds (string[] 合成シード), CoreTokens (string[] コア単語) }
    4. 修正時の注意点:
       - 文字化け（マルチバイト破壊）を防ぐため、日本語修飾子リテラルはASCIIエスケープまたはUTF8バイト配列で保持すること。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\google_suggest_fetcher.ps1"

function Get-GenreSynthesizedSeeds {
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$GenreObj,

        [Parameter(Mandatory=$true)]
        [string]$ConfigDir
    )

    $genreName = [string]$GenreObj.name
    $seeds = @($GenreObj.seeds)

    # 1. Extract core head terms (1-2 tokens) from catalog seeds
    $coreTokens = @()
    $rawSeedList = @()
    foreach ($s in $seeds) {
        $toks = ([string]$s) -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if ($toks.Count -ge 1 -and $toks[0].Length -ge 2) {
            $coreTokens += ([string]$toks[0]).Trim()
        }
        if ($toks.Count -ge 2) {
            $coreTokens += "$($toks[0]) $($toks[1])".Trim()
            $rawSeedList += "$($toks[0]) $($toks[1])".Trim()
        }
        if ($toks.Count -ge 3) {
            $rawSeedList += "$($toks[0]) $($toks[1]) $($toks[2])".Trim()
        }
        if ($toks.Count -ge 1) {
            $rawSeedList += ([string]$toks[0]).Trim()
        }
    }

    # Extract tokens from genre name (filter out placeholder labels like '予備枠')
    $cleanGenreName = $genreName -replace "(?i)予備枠[（\(]?", "" -replace "[）\)]", ""
    $nakaguro = [char]0x30FB
    $splitPattern = "[" + $nakaguro + "\s\/\(\)]+"
    $nameTokens = $cleanGenreName -split $splitPattern | Where-Object { $_.Length -ge 2 -and $_ -notmatch "^(?i)予備枠" }
    foreach ($nt in $nameTokens) {
        $coreTokens += ([string]$nt).Trim()
        $rawSeedList += ([string]$nt).Trim()
    }

    # 2. Base genre-specific longtail modifiers (Pure ASCII encoded UTF-8 strings)
    $headTerms = @($coreTokens | Where-Object { $_.Length -ge 2 -and $_.Length -le 10 } | Select-Object -Unique | Select-Object -First 10)
    $modOsusume    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x81,0x8A,0xE3,0x81,0x99,0xE3,0x81,0x99,0xE3,0x82,0x81))
    $modErabikata  = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE9,0x81,0xB8,0xE3,0x81,0xB3,0xE6,0x96,0xB9))
    $modShoshin    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0x88,0x9D,0xE5,0xBF,0x83,0xE8,0x80,0x85))
    $modYarikata   = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x82,0x84,0xE3,0x82,0x8A,0xE6,0x96,0xB9))
    $modKotsu      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x82,0xB3,0xE3,0x83,0x84))
    $modRanking    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0xA9,0xE3,0x83,0xB3,0xE3,0x82,0xAD,0xE3,0x83,0xB3,0xE3,0x82,0xB0))
    $modNinki      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE4,0xBA,0xBA,0xE6,0xB0,0x97))
    $modTeire      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0x89,0x8B,0xE5,0x85,0xA5,0xE3,0x82,0x8C))
    $modHikaku     = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0xAF,0x94,0xE8,0xBC,0x83))
    $modHajimekata = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0xA7,0x8B,0xE3,0x82,0x81,0xE6,0x96,0xB9))
    $modTsukaikata = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE4,0xBD,0xBF,0xE3,0x81,0x84,0xE6,0x96,0xB9))
    $modReview     = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0xAC,0xE3,0x83,0x93,0xE3,0x83,0xA5,0xE3,0x83,0xBC))
    $modHyoban     = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE8,0xA9,0x95,0xE5,0x88,0xA4))
    $modKuchikomi  = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0x8F,0xA3,0xE3,0x82,0xB3,0xE3,0x83,0x9F))
    $modHiyo       = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE8,0xB2,0xBB,0xE7,0x94,0xA8))
    $modMerit      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0xA1,0xE3,0x83,0xAA,0xE3,0x83,0x83,0xE3,0x83,0x88))
    $modKoka       = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE5,0x8A,0xB9,0xE6,0x9E,0x9C))
    $modTejun      = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0x89,0x8B,0xE9,0xA0,0x86))
    $modChuiten    = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE6,0xB3,0xA8,0xE6,0x84,0x8F,0xE7,0x82,0xB9))
    $modBlog       = [System.Text.Encoding]::UTF8.GetString([byte[]]@(0xE3,0x83,0x96,0xE3,0x83,0xAD,0xE3,0x82,0xB0))
    $modifiers = @(
        $modOsusume, $modErabikata, $modShoshin, $modYarikata, $modKotsu, $modRanking,
        $modNinki, $modTeire, $modHikaku, $modHajimekata, $modTsukaikata, $modReview,
        $modHyoban, $modKuchikomi, $modHiyo, $modMerit, $modKoka, $modTejun, $modChuiten, $modBlog
    )

    # 3. Dynamically load AI Daily Modifiers from external JSON (Zero token runtime cost)
    $aiConfigFile = Join-Path $ConfigDir "ai_daily_modifiers.json"
    $dynamicMods = @()
    if (Test-Path $aiConfigFile) {
        try {
            $aiConfigJson = [System.IO.File]::ReadAllText($aiConfigFile, [System.Text.Encoding]::UTF8)
            $aiConfigObj = $aiConfigJson | ConvertFrom-Json
            if ($aiConfigObj.universal_modifiers) {
                $dynamicMods += @($aiConfigObj.universal_modifiers)
            }
            if ($aiConfigObj.intent_categories) {
                foreach ($prop in $aiConfigObj.intent_categories.PSObject.Properties) {
                    $dynamicMods += @($prop.Value)
                }
            }
        } catch {}
    }

    $allModifiers = if ($dynamicMods.Count -gt 0) {
        @(@($dynamicMods) + @($modifiers)) | Select-Object -Unique
    } else {
        $modifiers
    }

    $longtailSeeds = @()
    foreach ($h in $headTerms) {
        foreach ($m in $allModifiers) {
            $longtailSeeds += "$h $m"
        }
    }

    # 4. Fetch live, real-time Google Autocomplete suggestions directly from head terms (Zero API Cost)
    $liveSuggestions = @()
    foreach ($h in ($headTerms | Select-Object -First 3)) {
        try {
            $sugs = Get-LiveGoogleSuggestions -Keyword $h -Limit 10
            if ($sugs -and $sugs.Count -gt 0) {
                $liveSuggestions += $sugs
            }
        } catch {}
    }

    # Priority order: 1. Live Google Autocomplete Suggestions, 2. Longtail combinations ($h $m), 3. Raw seeds
    $candidateSeeds = @($liveSuggestions) + @($longtailSeeds) + @($rawSeedList)
    $candidateSeeds = @($candidateSeeds | Select-Object -Unique)
    $coreTokens = @($coreTokens | Select-Object -Unique)

    return [PSCustomObject]@{
        CandidateSeeds = $candidateSeeds
        CoreTokens     = $coreTokens
    }
}
