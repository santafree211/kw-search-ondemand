<#
.SYNOPSIS
    engine_water_level_selector.ps1 - 最低水位ジャンル選定＆マイルストーン管理

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       50ジャンルの登録進捗をリアルタイム集計し、現在マイルストーン（初期目標: 全ジャンル18件）に達していない
       「最も登録件数が少ないジャンル」をボトムアップで選定・返却する。全ジャンル到達時はマイルストーンを自動繰り上げる。
    2. 準拠ルール:
       - GEMINI.md 第1条: 50ジャンル均等底上げ（マンガや100均など特定ジャンルへの偏重を禁止）。
    3. 入力・出力仕様:
       - Inputs : $Gender, $GenreMinId (int), $GenreMaxId (int), $VisitedGenres (hashtable)
       - Outputs: PSCustomObject (選定されたジャンルオブジェクト @{ Id, Name, Seeds, TotalCount... }) または $null
    4. 修正時の注意点:
       - 1サイクル内で同一ジャンルばかりが連続選定されないよう、$VisitedGenres hashtableで訪問済みを管理すること。
       - 全対象ジャンルがマイルストーンに到達した場合は、自動的にTargetを+2して底上げを継続すること。
#>

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. "$PSScriptRoot\genre_tracker.ps1"
. "$PSScriptRoot\guard_check_ymyl_kw.ps1"

function Select-NextWaterLevelGenre {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Gender,

        [Parameter(Mandatory=$false)]
        [int]$GenreMinId = 1,

        [Parameter(Mandatory=$false)]
        [int]$GenreMaxId = 50,

        [Parameter(Mandatory=$true)]
        [hashtable]$VisitedGenres
    )

    $report = Get-GenreProgressReport -Gender $Gender
    $wl = $report.WaterLevel
    Write-Output "`n[Water Level Status] Target: $($wl.CurrentMilestone) KWs/genre | Min: $($wl.MinKwsPerGenre) | Avg: $($wl.AvgKwsPerGenre) | Equitability: $($wl.EquitabilityScore)%"

    $sortedGenres = @($report.GenreStats | Sort-Object { [int]$_.TotalCount })
    $candidateGenres = @($sortedGenres | Where-Object {
        $idNum = [int]($_.Id -replace '\D', '')
        $yCheck = Test-GenreYmylEligibility -GenreObj $_
        $idNum -ge $GenreMinId -and $idNum -le $GenreMaxId -and [int]$_.TotalCount -lt $wl.CurrentMilestone -and $yCheck.IsAllowed
    })

    if ($candidateGenres.Count -eq 0) {
        $nextMilestone = $wl.CurrentMilestone + 2
        Write-Output ">>> All assigned genres ($GenreMinId-$GenreMaxId) reached milestone $($wl.CurrentMilestone)! Advancing to $nextMilestone..."
        $candidateGenres = @($sortedGenres | Where-Object {
            $idNum = [int]($_.Id -replace '\D', '')
            $yCheck = Test-GenreYmylEligibility -GenreObj $_
            $idNum -ge $GenreMinId -and $idNum -le $GenreMaxId -and [int]$_.TotalCount -lt $nextMilestone -and $yCheck.IsAllowed
        })
    }

    if ($candidateGenres.Count -eq 0) {
        Write-Output "All assigned genres ($GenreMinId-$GenreMaxId) have reached target! Stopping."
        return $null
    }

    $targetGenre = $null
    foreach ($cand in $candidateGenres) {
        if (-not $VisitedGenres.ContainsKey($cand.Id)) {
            $targetGenre = $cand
            break
        }
    }

    if ($null -eq $targetGenre) {
        Write-Output ">>> All eligible genres ($($VisitedGenres.Count)) visited in this cycle."
        Write-Output ">>> Resetting rotation to continue water-leveling towards daily quota exhaustion (403)..."
        $VisitedGenres.Clear()
        $targetGenre = $candidateGenres[0]
    }
    $VisitedGenres[$targetGenre.Id] = $true

    Write-Output "`n----------------------------------------------------------"
    Write-Output "Targeting Lowest Water-Level Genre: [$($targetGenre.Id)] $($targetGenre.Name)"
    Write-Output "Current Progress: $($targetGenre.TotalCount) / $($targetGenre.TargetCount) (Milestone Target: $($wl.CurrentMilestone))"
    Write-Output "----------------------------------------------------------"

    return $targetGenre
}
