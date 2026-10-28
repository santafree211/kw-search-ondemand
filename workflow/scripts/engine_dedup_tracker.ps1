<#
.SYNOPSIS
    engine_dedup_tracker.ps1 - 重複排除・過去SERP高速HashSetトラッカー

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       スプレッドシート全列（URL、KW1〜16）、異性間シート、およびSQLite過去SERP履歴を走査し、
       探索中の0ms高速重複判定を可能にするインメモリHashSet/Hashtableを初期化・保持する。
    2. 準拠ルール:
       - GEMINI.md 第2条: スプシ内での重複登録厳禁。
       - GEMINI.md 第3条: 異性シートKWとの重複排除。
    3. 入力・出力仕様:
       - Inputs : $SpreadsheetId, $TargetSheetName, $Gender, $KwStartCol
       - Outputs: PSCustomObject @{ RegisteredUrls, RegisteredKws, ExistingKws, SearchedSerpKeywords, OppositeGenderKws }
    4. 修正時の注意点:
       - URL判定はドメイン単位（www.除去、小文字化）で正規化すること。
       - KW判定はスペース区切りトークンをソートして結合し、語順の異なる同義KWも確実に弾くこと。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\sheet_data_reader.ps1"
. "$PSScriptRoot\sheet_cross_gender_guard.ps1"
. "$PSScriptRoot\db_sqlite_manager.ps1"

function Initialize-EngineDedupTracker {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SpreadsheetId,

        [Parameter(Mandatory=$true)]
        [string]$TargetSheetName,

        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$true)]
        [int]$KwStartCol
    )

    $sheetInitData = Read-SheetData -SheetId $SpreadsheetId -TargetSheetName $TargetSheetName
    $initRows = $sheetInitData.Rows

    $registeredUrls = @{}
    $registeredKws = @{}
    $existingKws = @()
    $starChar = [char]0x2606
    $parenPattern = "[\(" + [char]0xFF08 + "]([0-9]+)[\)" + [char]0xFF09 + "]"

    foreach ($r in $initRows) {
        # Check columns 1 to 5 for any URL or domain
        for ($cIdx = 1; $cIdx -le 5; $cIdx++) {
            if ($r.Count -gt $cIdx) {
                $uVal = ([string]$r[$cIdx]).Trim()
                if ($uVal.StartsWith("http")) {
                    try {
                        $uHost = ([System.Uri]$uVal).Host.ToLower()
                        if ($uHost.StartsWith("www.")) { $uHost = $uHost.Substring(4) }
                        $registeredUrls[$uHost] = $true
                    } catch {}
                } elseif ($uVal -match "^[a-z0-9-]+(\.[a-z0-9-]+)+$") {
                    $domClean = $uVal.ToLower()
                    if ($domClean.StartsWith("www.")) { $domClean = $domClean.Substring(4) }
                    $registeredUrls[$domClean] = $true
                }
            }
        }

        for ($c = $KwStartCol; $c -lt [Math]::Min($r.Count, ($KwStartCol + 16)); $c++) {
            $val = [string]$r[$c]
            if (-not [string]::IsNullOrWhiteSpace($val)) {
                $lines = $val -split "`r?`n"
                foreach ($l in $lines) {
                    $t = $l.Trim()
                    if ($t.StartsWith($starChar)) {
                        $existingKws += $t
                        $clean = $t -replace "^\s*[\u2605\u2606]+", ""
                        $clean = ($clean -replace $parenPattern, "").Trim()
                        $tokens = $clean -split "[\s\u3000]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
                        $norm = (($tokens | Sort-Object) -join " ").ToLower()
                        if (-not [string]::IsNullOrWhiteSpace($norm)) {
                            $registeredKws[$norm] = $true
                        }
                    }
                }
            }
        }
    }
    Write-Output "Initial Sheet State: $($initRows.Count) sites, $($existingKws.Count) keywords loaded (Uniqueness tracking active)."

    # Cross-Gender Keyword Exclusion (Barrier 1)
    try {
        $oppositeGender = if ($Gender -eq "male") { "female" } else { "male" }
        $oppMap = Get-CrossGenderKeywordMap -TargetGender $oppositeGender
        $oppAdded = 0
        if ($oppMap) {
            foreach ($k in $oppMap.Keys) {
                if (-not $registeredKws.ContainsKey($k)) {
                    $registeredKws[$k] = $true
                    $oppAdded++
                }
            }
        }
        Write-Output "Cross-Gender Exclusion Guard: Integrated $oppAdded registered keywords from $oppositeGender sheet (Total exclusion list: $($registeredKws.Count))."
    } catch {
        Write-Warning "Could not load cross-gender exclusion keywords: $($_.Exception.Message)"
    }

    # High-speed in-memory SERP HashSet
    $searchedSerpKeywords = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        $qRows = @(Invoke-SqliteQuery -SqlQuery "SELECT DISTINCT target_key FROM api_call_logs WHERE endpoint = 'serp_analysis';")
        foreach ($qr in $qRows) {
            if ($qr -and $qr.target_key) { [void]$searchedSerpKeywords.Add(([string]$qr.target_key).Trim()) }
        }
        $sRows = @(Invoke-SqliteQuery -SqlQuery "SELECT DISTINCT keyword FROM serp_cache;")
        foreach ($sr in $sRows) {
            if ($sr -and $sr.keyword) { [void]$searchedSerpKeywords.Add(([string]$sr.keyword).Trim()) }
        }
        Write-Output "In-Memory SERP Filter Active: Loaded $($searchedSerpKeywords.Count) historical keywords (0ms duplicate rejection)."
    } catch {
        Write-Warning "Failed to load historical SERP keywords into memory: $_"
    }

    return [PSCustomObject]@{
        RegisteredUrls       = $registeredUrls
        RegisteredKws        = $registeredKws
        ExistingKws          = $existingKws
        SearchedSerpKeywords = $searchedSerpKeywords
        ParenPattern         = $parenPattern
    }
}
