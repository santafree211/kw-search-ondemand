<#
.SYNOPSIS
    workflow/scripts/google_suggest_fetcher.ps1
    Responsibility: Directly retrieve live Google Autocomplete suggestions for real-time long-tail expansion.
    Zero-Cost: Completely free, no Ubersuggest API quota consumed.
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

$ErrorActionPreference = "Stop"

function Get-LiveGoogleSuggestions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Keyword,

        [Parameter(Mandatory=$false)]
        [int]$Limit = 15
    )

    $cleanKw = $Keyword.Trim()
    if ([string]::IsNullOrWhiteSpace($cleanKw)) {
        return @()
    }

    $encoded = [System.Uri]::EscapeDataString($cleanKw)
    $url = "https://suggestqueries.google.com/complete/search?client=chrome&hl=ja&q=$encoded"

    $results = @()
    try {
        $req = [System.Net.HttpWebRequest]::Create($url)
        $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        $req.Timeout = 5000

        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
        $jsonText = $reader.ReadToEnd()
        $reader.Close()
        $stream.Close()
        $resp.Close()

        if (-not [string]::IsNullOrWhiteSpace($jsonText)) {
            $parsed = $jsonText | ConvertFrom-Json
            if ($parsed -is [array] -and $parsed.Count -ge 2 -and $parsed[1]) {
                foreach ($sug in $parsed[1]) {
                    $sText = ([string]$sug).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($sText) -and $sText -ne $cleanKw) {
                        $results += $sText
                        if ($results.Count -ge $Limit) { break }
                    }
                }
            }
        }
    } catch {
        Write-Verbose "Google Suggest fetch error for '$cleanKw': $_"
    }

    # If limit allows, deepen search with Japanese hiragana vowels (あ, い, う, え, お, か...) to unearth 50+ long-tail gems
    if ($results.Count -lt $Limit) {
        $vowels = @("あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "さ", "し", "す", "せ", "そ", "た", "ち", "つ", "て", "と", "な", "に", "ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ", "ま", "み", "む", "め", "も", "や", "ゆ", "よ", "ら", "り", "る", "れ", "ろ", "わ")
        foreach ($v in $vowels) {
            if ($results.Count -ge $Limit) { break }
            $subQuery = "$cleanKw $v"
            $subEnc = [System.Uri]::EscapeDataString($subQuery)
            $subUrl = "https://suggestqueries.google.com/complete/search?client=chrome&hl=ja&q=$subEnc"
            try {
                $sReq = [System.Net.HttpWebRequest]::Create($subUrl)
                $sReq.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                $sReq.Timeout = 3000
                $sResp = $sReq.GetResponse()
                $sStream = $sResp.GetResponseStream()
                $sReader = New-Object System.IO.StreamReader($sStream, [System.Text.Encoding]::UTF8)
                $sJson = $sReader.ReadToEnd()
                $sReader.Close(); $sStream.Close(); $sResp.Close()
                if (-not [string]::IsNullOrWhiteSpace($sJson)) {
                    $sParsed = $sJson | ConvertFrom-Json
                    if ($sParsed -is [array] -and $sParsed.Count -ge 2 -and $sParsed[1]) {
                        foreach ($cand in $sParsed[1]) {
                            $cText = ([string]$cand).Trim()
                            if (-not [string]::IsNullOrWhiteSpace($cText) -and -not ($results -contains $cText)) {
                                $results += $cText
                                if ($results.Count -ge $Limit) { break }
                            }
                        }
                    }
                }
            } catch {}
        }
    }

    return @($results)
}
