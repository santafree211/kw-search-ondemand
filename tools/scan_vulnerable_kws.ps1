$blacklist = @('売り場', 'コーナー', '販売店', 'どこで売ってる', '店舗', 'サイズ', 'カバー', 'ケース', '通販', '楽天', 'Amazon')
$genders = @('female', 'male')

foreach ($g in $genders) {
    $p = data\cache\sheet_cache_$g.json
    if (Test-Path $p) {
        $data = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
        $vuln = @()
        foreach ($row in $data) {
            $kw = $row.kw
            if ($kw) {
                foreach ($b in $blacklist) {
                    if ($kw.IndexOf($b, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        $vuln += [PSCustomObject]@{
                            Row = $row.row
                            GenreNumber = $row.genre_number
                            GenreName = $row.genre_name
                            Site = $row.site_name
                            Url = $row.url
                            Kw = $kw
                            Star = $row.star
                            BadWord = $b
                        }
                        break
                    }
                }
            }
        }
        Write-Host [$g] Total rows: $($data.Count), Vulnerable: $($vuln.Count)
        $vuln | Format-Table Row, GenreNumber, Kw, Star, BadWord -AutoSize
    }
}