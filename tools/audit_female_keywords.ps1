param()

$projectRoot = $PSScriptRoot
if (-not $projectRoot) { $projectRoot = Get-Location }

. "$projectRoot\workflow\scripts\sheet_profile_resolver.ps1"
. "$projectRoot\workflow\scripts\sheet_data_reader.ps1"

$profile = Resolve-SheetProfile -Gender "female"
$data = Read-SheetData -SheetId $profile.SpreadsheetId -TargetSheetName $profile.TargetSheetName

Write-Host "Total Rows read from Female Sheet: $($data.RawValues.Count)"

$localPatterns = @("市", "区", "町", "村", "駅", "県", "東京", "大阪", "名古屋", "福岡", "横浜", "京都", "札幌", "仙台", "神戸", "広島", "埼玉", "千葉", "神奈川")
$entertainmentPatterns = @("アニメ", "漫画", "マンガ", "映画", "ドラマ", "ネタバレ", "結末", "考察", "最終回", "登場人物", "声優", "キャスト", "主題歌")

$foundViolations = @()

for ($r = 1; $r -lt $data.RawValues.Count; $r++) {
    $row = $data.RawValues[$r]
    $rowNum = $r + 1
    $siteName = if ($row.Count -gt 2) { $row[2] } else { "" }
    $siteUrl = if ($row.Count -gt 3) { $row[3] } else { "" }

    # Keywords are in columns G through N (index 6 through 13)
    for ($c = 6; $c -lt [Math]::Min($row.Count, 14); $c++) {
        $kw = $row[$c]
        if ($kw -and $kw.Trim() -ne "") {
            $kwClean = $kw.Trim()

            # Check Local patterns
            foreach ($lp in $localPatterns) {
                # Ensure it's not a generic word like '時計' matching '町'
                if ($kwClean -match $lp) {
                    $foundViolations += [PSCustomObject]@{
                        Row = $rowNum
                        Type = "地元・地域"
                        Pattern = $lp
                        Keyword = $kwClean
                        Site = $siteName
                    }
                }
            }

            # Check Entertainment patterns
            foreach ($ep in $entertainmentPatterns) {
                if ($kwClean -match $ep) {
                    $foundViolations += [PSCustomObject]@{
                        Row = $rowNum
                        Type = "エンタメ系"
                        Pattern = $ep
                        Keyword = $kwClean
                        Site = $siteName
                    }
                }
            }
        }
    }
}

Write-Host "`n=== DETECTED POTENTIAL VIOLATIONS IN FEMALE SHEET ==="
Write-Host "Total Flagged Items: $($foundViolations.Count)"
$foundViolations | Format-Table -AutoSize
