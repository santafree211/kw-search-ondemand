<#
.SYNOPSIS
    commit_param_parser.ps1 - コミット引数・JSON入力正規化モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       `tools/sheet_commit.ps1` への入力（CLI引数、-SiteJsonPathファイル、カンマ区切り文字列、ExtraArgs）を
       解析・平坦化し、正規化された単一の入力オブジェクトに整形して返す。
    2. 入力・出力仕様:
       - Inputs : $SiteJsonPath, $SiteName, $Url, $SiteKey, $Da, $OriginKw, $WinningKws, $GenreNumber, $GenreName, $ExtraArgs
       - Outputs: PSCustomObject @{ SiteName, Url, SiteKey, Da, OriginKw, WinningKws (string[]), GenreNumber, GenreName }
    3. 修正時の注意点:
       - カンマ区切りのKW（例: "☆☆KW1, ☆☆☆KW2"）や余剰引数はすべて分解・トリムして WinningKws 配列にフラット化すること。
#>

$ErrorActionPreference = "Stop"

function Parse-CommitParameters {
    param(
        [Parameter(Mandatory=$false)]
        [string]$SiteJsonPath = "",

        [Parameter(Mandatory=$false)]
        [string]$SiteName = "",

        [Parameter(Mandatory=$false)]
        [string]$Url = "",

        [Parameter(Mandatory=$false)]
        [string]$SiteKey = "",

        [Parameter(Mandatory=$false)]
        [int]$Da = 0,

        [Parameter(Mandatory=$false)]
        [string]$OriginKw = "",

        [Parameter(Mandatory=$false)]
        [string[]]$WinningKws = @(),

        [Parameter(Mandatory=$false)]
        [string]$GenreNumber = "",

        [Parameter(Mandatory=$false)]
        [string]$GenreName = "",

        [Parameter(Mandatory=$false)]
        [string[]]$ExtraArgs = @()
    )

    # 1. Parse JSON file if supplied
    if (-not [string]::IsNullOrWhiteSpace($SiteJsonPath) -and (Test-Path $SiteJsonPath)) {
        try {
            $text = [System.IO.File]::ReadAllText($SiteJsonPath, [System.Text.Encoding]::UTF8)
            $obj = $text | ConvertFrom-Json
            if ($obj.SiteName) { $SiteName = $obj.SiteName }
            if ($obj.Url) { $Url = $obj.Url }
            if ($obj.SiteKey) { $SiteKey = $obj.SiteKey }
            if ($obj.Da) { $Da = [int]$obj.Da }
            if ($obj.OriginKw) { $OriginKw = $obj.OriginKw }
            if ($obj.WinningKws) { $WinningKws = @($obj.WinningKws) }
            if ($obj.GenreNumber) { $GenreNumber = $obj.GenreNumber }
            if ($obj.GenreName) { $GenreName = $obj.GenreName }
        } catch {}
    }

    # 2. Flatten and normalize comma-separated keywords and ExtraArgs
    $expandedKws = @()
    $rawKwList = @($WinningKws) + @($ExtraArgs)
    foreach ($kw in $rawKwList) {
        if (-not [string]::IsNullOrWhiteSpace($kw)) {
            $parts = $kw -split ",\s*"
            foreach ($p in $parts) {
                $trimmed = $p.Trim()
                if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
                    $expandedKws += $trimmed
                }
            }
        }
    }

    return [PSCustomObject]@{
        SiteName    = $SiteName
        Url         = $Url
        SiteKey     = $SiteKey
        Da          = $Da
        OriginKw    = $OriginKw
        WinningKws  = $expandedKws
        GenreNumber = $GenreNumber
        GenreName   = $GenreName
    }
}
