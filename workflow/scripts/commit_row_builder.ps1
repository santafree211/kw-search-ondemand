<#
.SYNOPSIS
    commit_row_builder.ps1 - スプレッドシート行マージ・スプリット分割管理モジュール

.DESCRIPTION
    【設計メモ (AI Maintenance & Architecture Guide)】
    1. 単一責務:
       スプレッドシートの既存行を走査し、同一ドメインのサイトが存在する場合はその行の空きKW列（最大16KW）へマージ。
       16KWを超える場合は直後にスプリット継続行を新規挿入して全更新行データを生成する。
    2. 入力・出力仕様:
       - Inputs : $Header, $ExistingRows, $SiteName, $Url, $Da, $GenreNumber, $GenreName, $CommitKws, $SurveyDateFormatted, $KwStartCol
       - Outputs: object[] (ヘッダー＋全データ行の完全な配列)
    3. 修正時の注意点:
       - 1行に格納できるキーワードは最大16列まで。超過分は同一ドメイン情報のスプリット継続行を作成して直後に挿入すること。
       - 行自体のフォーマット作成は `commit_row_formatter.ps1` の `Build-SingleSiteRow` に委譲すること。
#>

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\commit_row_formatter.ps1"

function Build-UpdatedSheetRows {
    param(
        [Parameter(Mandatory=$true)]
        $Header,

        [Parameter(Mandatory=$true)]
        $ExistingRows,

        [Parameter(Mandatory=$true)]
        [string]$SiteName,

        [Parameter(Mandatory=$false)]
        [string]$Url = "",

        [Parameter(Mandatory=$true)]
        $Da,

        [Parameter(Mandatory=$true)]
        [string]$GenreNumber,

        [Parameter(Mandatory=$true)]
        [string]$GenreName,

        [Parameter(Mandatory=$true)]
        [string[]]$CommitKws,

        [Parameter(Mandatory=$true)]
        [string]$SurveyDateFormatted,

        [Parameter(Mandatory=$true)]
        [int]$KwStartCol
    )

    $statusText = [System.Text.Encoding]::UTF8.GetString(@(0xF0,0x9F,0x9F,0xA2,0x20,0xE8,0xAA,0xBF,0xE6,0x9F,0xBB,0xE6,0xB8,0x88,0xE3,0x83,0xBB,0xE7,0x99,0xBB,0xE9,0x8C,0xB2,0xE5,0xAE,0x8C,0xE4,0xBA,0x86))

    $targetDomain = ""
    if (-not [string]::IsNullOrWhiteSpace($Url)) {
        try {
            $uri = [System.Uri]$Url
            $targetDomain = $uri.Host.ToLower().Trim()
            if ($targetDomain.StartsWith("www.")) { $targetDomain = $targetDomain.Substring(4) }
        } catch {
            $targetDomain = $Url.ToLower().Trim()
        }
    }

    $urlColIdx = 4
    for ($i = 0; $i -lt $Header.Count; $i++) {
        $h = [string]$Header[$i]
        if ($h -match "URL" -or $h -match "代表URL") {
            $urlColIdx = $i
            break
        }
    }

    $existingSiteRowIndex = -1
    if (-not [string]::IsNullOrWhiteSpace($targetDomain)) {
        for ($r = 0; $r -lt $ExistingRows.Count; $r++) {
            $rUrl = if ($ExistingRows[$r].Count -gt $urlColIdx) { ([string]$ExistingRows[$r][$urlColIdx]).Trim() } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($rUrl)) {
                $rDom = ""
                try {
                    $rUri = [System.Uri]$rUrl
                    $rDom = $rUri.Host.ToLower().Trim()
                    if ($rDom.StartsWith("www.")) { $rDom = $rDom.Substring(4) }
                } catch {
                    $rDom = $rUrl.ToLower().Trim()
                }
                if ($rDom -eq $targetDomain) {
                    $existingSiteRowIndex = $r
                    break
                }
            }
        }
    }

    if ($existingSiteRowIndex -ge 0) {
        Write-Host "Commit guard: Site domain '$targetDomain' already exists at Row $($existingSiteRowIndex + 2). Merging keywords with 16-KW limit per row."
        $rowsList = [System.Collections.Generic.List[object]]::new($ExistingRows)
        
        $siteRowIndices = [System.Collections.Generic.List[int]]::new()
        $siteRowIndices.Add($existingSiteRowIndex)
        $chkIdx = $existingSiteRowIndex + 1
        while ($chkIdx -lt $rowsList.Count) {
            $cUrl = if ($rowsList[$chkIdx].Count -gt $urlColIdx) { ([string]$rowsList[$chkIdx][$urlColIdx]).Trim() } else { "" }
            $cDom = ""
            try {
                $cUri = [System.Uri]$cUrl
                $cDom = $cUri.Host.ToLower().Trim()
                if ($cDom.StartsWith("www.")) { $cDom = $cDom.Substring(4) }
            } catch { $cDom = $cUrl.ToLower().Trim() }
            if ($cDom -eq $targetDomain) {
                $siteRowIndices.Add($chkIdx)
                $chkIdx++
            } else {
                break
            }
        }

        $allExistingKws = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($rIdx in $siteRowIndices) {
            $rData = $rowsList[$rIdx]
            for ($c = $KwStartCol; $c -lt [Math]::Min($rData.Count, ($KwStartCol + 16)); $c++) {
                $v = [string]$rData[$c]
                if (-not [string]::IsNullOrWhiteSpace($v)) {
                    [void]$allExistingKws.Add($v.Trim())
                }
            }
        }

        $toAdd = New-Object System.Collections.Generic.List[string]
        foreach ($ck in $CommitKws) {
            if (-not $allExistingKws.Contains($ck)) {
                $toAdd.Add($ck)
            }
        }

        foreach ($rIdx in $siteRowIndices) {
            if ($toAdd.Count -eq 0) { break }
            $rList = [System.Collections.ArrayList]@($rowsList[$rIdx])
            while ($rList.Count -lt 25) { [void]$rList.Add("") }
            
            $rowKws = New-Object System.Collections.Generic.List[string]
            for ($c = $KwStartCol; $c -le ($KwStartCol + 15); $c++) {
                $val = [string]$rList[$c]
                if (-not [string]::IsNullOrWhiteSpace($val)) {
                    $rowKws.Add($val.Trim())
                } elseif ($toAdd.Count -gt 0) {
                    $nxt = $toAdd[0]
                    $toAdd.RemoveAt(0)
                    $rList[$c] = $nxt
                    $rowKws.Add($nxt)
                }
            }

            $rList[22] = Get-CommitStarDisplayString -Keywords $rowKws
            if ([string]::IsNullOrWhiteSpace([string]$rList[23])) {
                $rList[23] = $SurveyDateFormatted
            }
            $rowsList[$rIdx] = $rList
        }

        $insertPos = $siteRowIndices[$siteRowIndices.Count - 1] + 1
        $baseRow = $rowsList[$existingSiteRowIndex]
        $bStatus = if ($baseRow.Count -gt 0) { [string]$baseRow[0] } else { $statusText }
        $bGenreNo = if ($baseRow.Count -gt 1) { [string]$baseRow[1] } else { $GenreNumber }
        $bGenreNm = if ($baseRow.Count -gt 2) { [string]$baseRow[2] } else { $GenreName }
        $bSiteNm = if ($baseRow.Count -gt 3) { [string]$baseRow[3] } else { $SiteName }
        $bUrl = if ($baseRow.Count -gt 4) { [string]$baseRow[4] } else { $Url }
        $bDa = if ($baseRow.Count -gt 5) { $baseRow[5] } else { $Da }

        while ($toAdd.Count -gt 0) {
            $chunkSize = [Math]::Min(16, $toAdd.Count)
            $chunkKws = @()
            for ($k = 0; $k -lt $chunkSize; $k++) {
                $chunkKws += $toAdd[0]
                $toAdd.RemoveAt(0)
            }

            $splitRow = Build-SingleSiteRow -Status $bStatus -GenreNo $bGenreNo -GenreNm $bGenreNm -SiteNm $bSiteNm -SiteUrl $bUrl -SiteDa $bDa -Keywords $chunkKws -DateFormatted $SurveyDateFormatted
            $rowsList.Insert($insertPos, $splitRow)
            $insertPos++
        }

        return @(,$Header) + @($rowsList)
    } else {
        $newRowsToAppend = @()
        $kList = @($CommitKws)
        for ($i = 0; $i -lt $kList.Count; $i += 16) {
            $endIdx = [Math]::Min($i + 15, $kList.Count - 1)
            $chunkKws = @($kList[$i..$endIdx])
            $chunkRow = Build-SingleSiteRow -Status $statusText -GenreNo $GenreNumber -GenreNm $GenreName -SiteNm $SiteName -SiteUrl $Url -SiteDa $Da -Keywords $chunkKws -DateFormatted $SurveyDateFormatted
            $newRowsToAppend += ,$chunkRow
        }

        return @(,$Header) + @($ExistingRows) + $newRowsToAppend
    }
}
